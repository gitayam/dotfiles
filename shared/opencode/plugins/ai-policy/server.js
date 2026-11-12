// OpenCode 2.x plugin: before every agent model request, ask ai-policy whether
// this project may use the request's provider and model. Throwing from the
// "context" hook stops the request; the run ends with the policy message.
// Installed by linking this directory to ~/.config/opencode/plugins/ai-policy.
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AI_POLICY = process.env.AI_POLICY_BIN || join(dirname(fileURLToPath(import.meta.url)), "../../../bin/ai-policy");
const cache = new Map(); // "dir\0model" -> { at, error }

function check(directory, model) {
  const key = `${directory}\0${model}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < 60_000) return hit.error;
  let error = null;
  try {
    execFileSync(AI_POLICY, ["check", "--cwd", directory, "--model", model], { stdio: ["ignore", "ignore", "pipe"], timeout: 15_000 });
  } catch (e) {
    const detail = e.stderr?.toString().trim();
    error = e.status === 3 ? detail || `ai-policy: ${model} is prohibited here`
      : `ai-policy check failed (${e.status ?? e.code}); blocking until it works. ${detail ?? ""}`.trim();
  }
  cache.set(key, { at: Date.now(), error });
  return error;
}

export default {
  id: "ai-policy",
  async setup(ctx) {
    await ctx.session.hook("context", (event) => {
      const directory = ctx.location?.directory || process.cwd();
      const error = check(directory, `${event.model.providerID}/${event.model.id}`);
      if (error) throw new Error(error);
    });
  },
};
