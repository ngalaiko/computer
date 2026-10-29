import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerOyoWatch } from "./watch.mjs";

export default function (pi: ExtensionAPI) {
  registerOyoWatch(pi, Type);
}
