import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerSessionName } from "./name.mjs";

export default function (pi: ExtensionAPI) {
  registerSessionName(pi, Type);
}
