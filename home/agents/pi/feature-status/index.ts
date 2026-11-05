import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerFeatureStatus } from "./status.mjs";

export default function (pi: ExtensionAPI) {
  registerFeatureStatus(pi, Type);
}
