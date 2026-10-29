import type { HunkExtensionAPI } from "hunkdiff/extension";
import bridge from "./bridge.ts";
import { createIssuesPane } from "./pane.tsx";

export default function (hunk: HunkExtensionAPI) {
  bridge(hunk, { renderPane: createIssuesPane });
}
