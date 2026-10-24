import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const compact = (n: number) =>
  n >= 1_000_000
    ? `${+(n / 1_000_000).toFixed(1)}m`
    : n >= 1000
      ? `${+(n / 1000).toFixed(1)}k`
      : `${n}`;

export default function (pi: ExtensionAPI) {
  let refresh = async () => {};
  let dispose = () => {};

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    dispose();
    ctx.ui.setFooter((tui, theme, footerData) => {
      let label = "";
      let pending = false;
      let disposed = false;
      const home = homedir();
      const cwd =
        ctx.cwd === home
          ? "~"
          : ctx.cwd.startsWith(`${home}/`)
            ? `~${ctx.cwd.slice(home.length)}`
            : ctx.cwd;

      refresh = async () => {
        if (pending || disposed) return;
        pending = true;
        let next = "";
        try {
          const query = (revision: string, template: string) =>
            pi.exec(
              "jj",
              [
                "--ignore-working-copy",
                "--color",
                "always",
                "log",
                "--no-graph",
                "-r",
                revision,
                "-T",
                template,
              ],
              { cwd: ctx.cwd, timeout: 2000 },
            );
          const at = await query(
            "@",
            'local_bookmarks.join(", ") ++ "\\n" ++ change_id.shortest(4) ++ " " ++ commit_id.shortest(4) ++ " " ++ if(empty, "clean", "dirty")',
          );
          if (at.code === 0) {
            const [bookmarks, ids] = at.stdout.trimEnd().split("\n");
            let prefix = bookmarks;
            if (!prefix) {
              const base = "heads(::@ & bookmarks())";
              const [closest, ahead] = await Promise.all([
                query(base, '\'~\' ++ local_bookmarks.join(", ~") ++ "\\n"'),
                query(`${base}::@- ~ ${base}`, '"x"'),
              ]);
              prefix =
                closest.code === 0
                  ? closest.stdout.trim().split("\n").filter(Boolean).join(", ")
                  : "";
              const count = ahead.code === 0 ? ahead.stdout.trim().length : 0;
              if (prefix && count) prefix += ` +${count}`;
            }
            next = `[${prefix ? `${prefix} ` : ""}${ids}]`.replace(
              /\x1b\[[0-9;]*m|[\x00-\x1f\x7f-\x9f]/g,
              (part) => (part.startsWith("\x1b[") ? part : ""),
            );
          }
        } catch {
          // jj unavailable.
        } finally {
          pending = false;
        }
        if (!disposed && next !== label) {
          label = next;
          tui.requestRender();
        }
      };
      void refresh();
      const timer = setInterval(() => void refresh(), 5000);
      timer.unref();
      dispose = () => {
        disposed = true;
        clearInterval(timer);
      };

      return {
        dispose,
        invalidate() {},
        render(width: number): string[] {
          const usage = ctx.getContextUsage();
          const window = usage?.contextWindow ?? ctx.model?.contextWindow;
          const context = window
            ? `ctx ${usage?.percent == null ? "?" : `${usage.percent.toFixed(1)}%`}/${compact(window)}`
            : "ctx ?";
          const model = ctx.model
            ? `(${ctx.model.provider}) ${ctx.model.id}`
            : "no model";
          const modelInfo = truncateToWidth(
            `${model} · ${pi.getThinkingLevel()}`,
            Math.max(0, width - visibleWidth(context) - 3),
          );
          const right = modelInfo ? `${modelInfo} · ${context}` : context;
          const statuses = [...footerData.getExtensionStatuses().values()];
          const left = truncateToWidth(
            [`${cwd}${label ? ` ${label}` : ""}`, ...statuses].join(" · "),
            Math.max(0, width - visibleWidth(right) - 1),
          );
          const gap = " ".repeat(
            Math.max(1, width - visibleWidth(left) - visibleWidth(right)),
          );
          return [
            theme.fg(
              "dim",
              truncateToWidth(
                visibleWidth(context) >= width ? context : left + gap + right,
                width,
              ),
            ),
          ];
        },
      };
    });
  });

  pi.on("agent_end", () => refresh());
  pi.on("session_shutdown", () => dispose());
}
