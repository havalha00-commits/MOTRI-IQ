import { Router } from "express";
import { authenticateCurrentUser } from "../middleware/current_user.js";
import { UGC_POLICY_VERSION, ugcPolicy } from "../services/ugc_policy.js";

export function createUgcRouter({
  authenticate = authenticateCurrentUser,
  policy = ugcPolicy
} = {}) {
  const router = Router();
  router.use(authenticate);

  router.get("/acceptance", async (req, res) => {
    try {
      const accepted = await policy.hasAccepted(req);
      return res.json({
        success: true,
        data: { accepted, policy_version: UGC_POLICY_VERSION }
      });
    } catch (error) {
      console.error("UGC policy status check failed:", error.message);
      return res.status(503).json({ error: "UGC policy status is unavailable" });
    }
  });

  router.post("/acceptance", async (req, res) => {
    if (req.body?.policy_version !== UGC_POLICY_VERSION) {
      return res.status(400).json({ error: "Invalid UGC policy version" });
    }
    try {
      const accepted = await policy.accept(req);
      if (!accepted) {
        return res.status(409).json({ error: "UGC policy acceptance was not saved" });
      }
      return res.json({
        success: true,
        data: { accepted: true, policy_version: UGC_POLICY_VERSION }
      });
    } catch (error) {
      console.error("UGC policy acceptance failed:", error.message);
      return res.status(503).json({ error: "UGC policy acceptance is unavailable" });
    }
  });

  return router;
}

export default createUgcRouter();
