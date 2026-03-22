/**
 * Minimal tmux extension for herdr integration testing.
 *
 * Two actions: send and read. No wait, no pane creation, no discovery loops.
 * Talks directly to a pane tagged @pi_name=herdr.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { StringEnum } from "@mariozechner/pi-ai";
import { Text } from "@mariozechner/pi-tui";
import { Type } from "@sinclair/typebox";

function stripAnsi(text: string): string {
	return text
		.replace(/\x1b\].*?(?:\x07|\x1b\\)/g, "")
		.replace(/\x1bPtmux;.*?\x1b\\/g, "")
		.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")
		.replace(/\x1b[^[\]P]/g, "")
		.replace(/\r/g, "");
}

export default function (pi: ExtensionAPI) {
	let herdrPaneId: string | null = null;
	let windowId: string | null = null;

	pi.on("session_start", async () => {
		if (!process.env.TMUX) return;

		try {
			const winResult = await pi.exec("tmux", [
				"display-message", "-p", "-t", process.env.TMUX_PANE || "",
				"#{window_id}",
			]);
			if (winResult.code === 0) windowId = winResult.stdout.trim();

			if (windowId) {
				const listResult = await pi.exec("tmux", [
					"list-panes", "-t", windowId,
					"-F", "#{pane_id}\t#{@pi_name}",
				]);
				if (listResult.code === 0) {
					for (const line of listResult.stdout.trim().split("\n")) {
						const [paneId, name] = line.split("\t");
						if (name === "herdr") {
							herdrPaneId = paneId;
							break;
						}
					}
				}
			}
		} catch {}
	});

	pi.registerTool({
		name: "herdr",
		label: "herdr",
		description:
			"Interact with the herdr instance under test. " +
			"Actions: send (send keys or text to herdr), read (capture herdr screen).",
		parameters: Type.Object({
			action: StringEnum(["send", "read"] as const, {
				description: "Action: send or read",
			}),
			keys: Type.Optional(
				Type.String({
					description:
						"Keys to send, space-separated (for send). Examples: C-s, Enter, n, v, Escape",
				}),
			),
			text: Type.Optional(
				Type.String({ description: "Literal text to type (for send). Sent as-is." }),
			),
			lines: Type.Optional(
				Type.Number({ description: "Scrollback lines to capture (for read, default: 50)" }),
			),
		}),

		async execute(_toolCallId, params) {
			if (!herdrPaneId) {
				throw new Error("herdr pane not found. Is herdr running in this tmux window?");
			}

			switch (params.action) {
				case "send": {
					if (!params.keys && !params.text) {
						throw new Error("send requires 'keys' or 'text'");
					}
					if (params.text) {
						await pi.exec("tmux", [
							"send-keys", "-l", "-t", herdrPaneId, params.text,
						]);
					}
					if (params.keys) {
						const keyArgs = params.keys.split(/\s+/).filter(Boolean);
						await pi.exec("tmux", [
							"send-keys", "-t", herdrPaneId, ...keyArgs,
						]);
					}
					const desc = [
						params.text && `"${params.text}"`,
						params.keys,
					].filter(Boolean).join(" + ");
					return {
						content: [{ type: "text", text: `Sent: ${desc}` }],
					};
				}

				case "read": {
					const lines = params.lines ?? 50;
					const result = await pi.exec("tmux", [
						"capture-pane", "-t", herdrPaneId, "-p", "-S", `-${lines}`,
					]);
					if (result.code !== 0) {
						throw new Error(`capture-pane failed: ${result.stderr}`);
					}
					let output = stripAnsi(result.stdout);
					output = output.replace(/\n+$/, "\n");
					return {
						content: [{ type: "text", text: output }],
					};
				}

				default:
					throw new Error(`Unknown action: ${params.action}`);
			}
		},

		renderCall(args, theme) {
			const action = args.action || "?";
			let t = theme.fg("toolTitle", theme.bold("herdr "));
			t += theme.fg("accent", action);
			if (args.text) t += theme.fg("dim", ` "${args.text}"`);
			if (args.keys) t += theme.fg("dim", ` ${args.keys}`);
			return new Text(t, 0, 0);
		},

		renderResult(result, _opts, theme) {
			const c = result.content?.[0];
			const text = c?.type === "text" ? c.text : "";
			if (text.length > 200) {
				return new Text(theme.fg("dim", text.slice(0, 200) + "…"), 0, 0);
			}
			return new Text(theme.fg("dim", text), 0, 0);
		},
	});
}
