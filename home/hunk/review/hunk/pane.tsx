/** @jsxImportSource @opentui/react */
import {
  useEffect,
  useLayoutEffect,
  useRef,
  useSyncExternalStore,
} from "react";
import type { ScrollBoxRenderable } from "@opentui/core";
import type { ExtensionPaneProps } from "hunkdiff/extension";
import {
  createIssuesPaneController,
  watchIssueSelection,
  issueRowId,
} from "./pane.mjs";

export function createIssuesPane(
  controller: ReturnType<typeof createIssuesPaneController>,
) {
  return function IssuesPane(props: ExtensionPaneProps) {
    const state = useSyncExternalStore(
      controller.subscribe,
      controller.getSnapshot,
    );
    const scrollRef = useRef<ScrollBoxRenderable | null>(null);
    const { theme, width, height } = props;
    const selected = state.rows.find((row) => row.id === state.selectedId);
    const ready =
      state.available && state.generation === props.reviewGeneration;

    useLayoutEffect(() => controller.frame(props, state), [props, state]);
    useEffect(() => () => controller.unmount(), []);
    useEffect(
      () => watchIssueSelection(scrollRef.current, state.selectedId),
      [state.selectedId, state.rows.length, height],
    );

    return (
      <box
        style={{
          width,
          height,
          flexDirection: "column",
          backgroundColor: theme.panel,
          overflow: "hidden",
        }}
      >
        <text
          height={1}
          flexShrink={0}
          content={
            state.focused
              ? " j/k ↑/↓ · Space toggle · Enter Go"
              : " ,i keys · click selects only"
          }
          fg={theme.muted}
        />
        <text
          height={1}
          flexShrink={0}
          content={
            ready
              ? ` Issues · ${state.rows.filter((row) => row.status === "open").length} open · ${state.rows.length} human threads`
              : " Issues unavailable · ,i refresh"
          }
          fg={theme.accent}
        />
        <scrollbox
          ref={scrollRef}
          width="100%"
          height={Math.max(0, height - 3)}
          flexShrink={0}
          focused={false}
          scrollY={true}
          rootOptions={{ backgroundColor: theme.panel }}
          wrapperOptions={{ backgroundColor: theme.panel }}
          viewportOptions={{ backgroundColor: theme.panel }}
          contentOptions={{ backgroundColor: theme.panel }}
          horizontalScrollbarOptions={{ visible: false }}
        >
          {ready ? (
            state.rows.map((row) => {
              const active = row.id === state.selectedId;
              const bg = active ? theme.selectedHunk : theme.panel;
              return (
                <box
                  key={row.id}
                  id={issueRowId(row.id)}
                  style={{
                    width: "100%",
                    height: 3,
                    flexShrink: 0,
                    flexDirection: "column",
                    backgroundColor: bg,
                    overflow: "hidden",
                  }}
                >
                  <text
                    height={1}
                    content={` ${active ? ">" : " "} ${row.status === "open" ? "○ Open" : "✓ Resolved"}`}
                    fg={active ? theme.accent : theme.text}
                    bg={bg}
                    onMouseDown={(event) => {
                      if (event.button === 0)
                        controller.select(row.id, state, props);
                    }}
                  />
                  <text
                    height={1}
                    content={` ${row.label}`}
                    fg={theme.muted}
                    bg={bg}
                    onMouseDown={(event) => {
                      if (event.button === 0)
                        controller.select(row.id, state, props);
                    }}
                  />
                  <text
                    height={1}
                    content={` ${row.preview}`}
                    fg={theme.text}
                    bg={bg}
                    onMouseDown={(event) => {
                      if (event.button === 0)
                        controller.select(row.id, state, props);
                    }}
                  />
                </box>
              );
            })
          ) : (
            <text
              content={` ${state.error ?? "Saved-note snapshot required"}`}
              fg={theme.muted}
            />
          )}
          {ready && !state.rows.length ? (
            <text content=" No human issues" fg={theme.muted} />
          ) : null}
        </scrollbox>
        <box
          style={{
            width: "100%",
            height: 1,
            flexShrink: 0,
            flexDirection: "row",
          }}
        >
          <text
            content={` [${selected?.status === "resolved" ? "Reopen" : "Resolve"}] `}
            fg={ready && selected ? theme.accent : theme.muted}
            onMouseUp={(event) => {
              if (event.button === 0) controller.toggle(state, props);
            }}
          />
          <text
            content=" [Go]"
            fg={
              ready && selected?.locationVerified ? theme.accent : theme.muted
            }
            onMouseUp={(event) => {
              if (event.button === 0) controller.go(state, props);
            }}
          />
        </box>
      </box>
    );
  };
}
