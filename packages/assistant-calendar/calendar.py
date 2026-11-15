"""Small CalDAV CLI; credentials stay in the consumer process, not argv/output."""

import argparse
from datetime import date, datetime, timezone
import json
import logging
import os
import subprocess
import sys
from urllib.parse import urlparse
import uuid

import caldav
from icalendar import Calendar, Event


class CalendarError(Exception):
    pass


def timestamp(value):
    try:
        if len(value) == 10:
            return date.fromisoformat(value)
        result = datetime.fromisoformat(value)
        if result.utcoffset() is None:
            raise ValueError
        # Fixed offsets are instants, not named TZIDs with VTIMEZONE definitions.
        return result.astimezone(timezone.utc)
    except ValueError:
        raise CalendarError(
            "Use an ISO date or a datetime with an explicit UTC offset."
        )


def interval(start, end):
    start, end = timestamp(start), timestamp(end)
    if type(start) is not type(end) or end <= start:
        raise CalendarError(
            "Start/end must have the same type and end must follow start."
        )
    return start, end


def describe(resource):
    result = []
    for event in resource.icalendar_instance.walk("VEVENT"):
        item = {"url": str(resource.url), "etag": resource.etag}
        for key in ("UID", "SUMMARY", "LOCATION", "STATUS", "TRANSP"):
            item[key.lower()] = str(event[key]) if key in event else None
        item["duration"] = (
            event["DURATION"].to_ical().decode() if "DURATION" in event else None
        )
        for key in ("DTSTART", "DTEND", "RECURRENCE-ID"):
            item[key.lower()] = event[key].dt.isoformat() if key in event else None
        item["all_day"] = "DTSTART" in event and not isinstance(
            event["DTSTART"].dt, datetime
        )
        result.append(item)
    return result


def editable(resource):
    events = resource.icalendar_instance.walk("VEVENT")
    if len(events) != 1 or any(
        key in events[0]
        for key in (
            "RRULE",
            "RDATE",
            "EXDATE",
            "RECURRENCE-ID",
            "ATTENDEE",
            "ORGANIZER",
        )
    ):
        raise CalendarError(
            "Recurring events and invitation-bearing events are read-only in this tool."
        )
    return events[0]


def check_response(response):
    if response.status == 412:
        raise CalendarError(
            "Precondition failed: event changed or already exists. Read it again; do not retry blindly."
        )
    if response.status not in (200, 201, 204):
        raise CalendarError(
            f"CalDAV write returned HTTP {response.status}; verify state before retrying."
        )


def run(args):
    endpoint = os.environ.get("CALDAV_URL", "https://caldav.icloud.com/")
    parsed = urlparse(endpoint)
    if (
        parsed.username
        or parsed.password
        or not (
            parsed.scheme == "https"
            or (
                parsed.scheme == "http"
                and parsed.hostname in ("localhost", "127.0.0.1", "::1")
            )
        )
    ):
        raise CalendarError(
            "CalDAV requires HTTPS (HTTP loopback is allowed for local tests), without URL credentials."
        )
    username = os.environ.get("ICLOUD_ACCOUNT")
    store = os.environ.get("ASSISTANT_SECRETS_FILE")
    if not username or not store or not os.path.isabs(store):
        raise CalendarError(
            "Configure ICLOUD_ACCOUNT and an absolute external ASSISTANT_SECRETS_FILE path."
        )
    secret = subprocess.run(
        ["sops", "decrypt", "--extract", '["icloud"]["app_password"]', store],
        capture_output=True,
        text=True,
    )
    if secret.returncode or not secret.stdout.strip():
        raise CalendarError(
            "SOPS credential retrieval failed; check the external store and age identity."
        )
    with caldav.DAVClient(
        url=endpoint, username=username, password=secret.stdout.rstrip("\n"), timeout=30
    ) as client:
        calendars = client.principal().calendars()
        if args.command == "calendars":
            return [{"name": str(c.name), "url": str(c.url)} for c in calendars]
        selected = [c for c in calendars if str(c.url) == args.calendar]
        if len(selected) != 1:
            raise CalendarError(
                "Select an exact calendar URL returned by the calendars command."
            )
        calendar = selected[0]
        if args.command == "events":
            start, end = interval(args.start, args.end)
            if not isinstance(start, datetime):
                raise CalendarError(
                    "Agenda queries require offset-aware datetime boundaries, not dates."
                )
            return [
                item
                for resource in calendar.search(
                    start=start, end=end, event=True, expand=True
                )
                for item in describe(resource)
            ]
        if args.command == "create":
            start, end = interval(args.start, args.end)
            event = Event()
            for key, value in {
                "uid": args.uid,
                "summary": args.summary,
                "dtstart": start,
                "dtend": end,
                "dtstamp": datetime.now(timezone.utc),
            }.items():
                event.add(key, value)
            data = Calendar()
            data.add("version", "2.0")
            data.add("prodid", "-//Personal assistant//Calendar//EN")
            data.add_component(event)
            url = (
                str(calendar.url).rstrip("/")
                + "/"
                + uuid.uuid5(uuid.NAMESPACE_URL, args.uid).hex
                + ".ics"
            )
            check_response(
                client.put(
                    url,
                    data.to_ical(),
                    headers={
                        "Content-Type": "text/calendar; charset=utf-8",
                        "If-None-Match": "*",
                    },
                )
            )
            saved = calendar.event_by_uid(args.uid).load()
            return describe(saved)
        resource = calendar.event_by_uid(args.uid).load()
        if args.command == "get":
            return [dict(item, icalendar=resource.data) for item in describe(resource)]
        event = editable(resource)
        if (
            not resource.etag
            or resource.etag.startswith("W/")
            or resource.etag != args.etag
        ):
            raise CalendarError(
                "A current strong ETag from get is required; read the event again."
            )
        if args.command == "delete":
            check_response(
                client.request(
                    str(resource.url), "DELETE", headers={"If-Match": args.etag}
                )
            )
            if client.request(str(resource.url), "GET").status != 404:
                raise CalendarError(
                    "Deletion could not be verified; inspect state before retrying."
                )
            return {"deleted": args.uid, "url": str(resource.url)}
        changes = {}
        for key in ("summary", "location"):
            if getattr(args, key) is not None:
                changes[key.upper()] = getattr(args, key)
        if args.start is not None or args.end is not None:
            if args.start is None or args.end is None:
                raise CalendarError(
                    "Changing event time requires both --start and --end."
                )
            start, end = interval(args.start, args.end)
            changes.update(DTSTART=start, DTEND=end)
        if not changes:
            raise CalendarError(
                "Update requires a changed summary, location, or start/end."
            )
        for key, value in changes.items():
            event.pop(key, None)
            event.add(key, value)
        if "DTEND" in changes:
            event.pop("DURATION", None)
        event["SEQUENCE"] = int(event.get("SEQUENCE", 0)) + 1
        event.pop("DTSTAMP", None)
        event.add("DTSTAMP", datetime.now(timezone.utc))
        check_response(
            client.put(
                str(resource.url),
                resource.icalendar_instance.to_ical(),
                headers={
                    "Content-Type": "text/calendar; charset=utf-8",
                    "If-Match": args.etag,
                },
            )
        )
        saved = calendar.event_by_uid(args.uid).load()
        actual = saved.icalendar_component
        for key, expected in changes.items():
            value = actual[key].dt if key in ("DTSTART", "DTEND") else str(actual[key])
            if value != expected:
                raise CalendarError(
                    "Update read-back differs from the request; inspect state before retrying."
                )
        return describe(saved)


def main():
    parser = argparse.ArgumentParser(
        prog="assistant-calendar",
        description="iCloud CalDAV JSON CLI with SOPS credentials.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("calendars")
    for command in ("events", "get", "create", "update", "delete"):
        sub = commands.add_parser(command)
        sub.add_argument(
            "--calendar", required=True, help="Exact discovered calendar URL"
        )
        if command != "events":
            sub.add_argument(
                "--uid",
                required=True,
                help="Exact UID; reuse for uncertain create outcomes",
            )
        if command in ("update", "delete"):
            sub.add_argument(
                "--etag", required=True, help="Reviewed ETag returned by get"
            )
        if command in ("events", "create", "update"):
            sub.add_argument("--start", required=command != "update")
            sub.add_argument("--end", required=command != "update")
        if command in ("create", "update"):
            sub.add_argument("--summary", required=command == "create")
        if command == "update":
            sub.add_argument("--location")
    args = parser.parse_args()
    logging.disable(logging.CRITICAL)
    try:
        print(json.dumps(run(args), ensure_ascii=False))
    except CalendarError as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1
    except Exception as exc:
        # Library/HTTP exceptions can include auth data. Never echo them.
        print(
            json.dumps(
                {
                    "error": f"Calendar operation failed ({type(exc).__name__}); verify state before retrying."
                }
            ),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
