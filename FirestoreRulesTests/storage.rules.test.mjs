import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import { getBytes, ref, uploadBytes } from "firebase/storage";

// storage.rules reads Firestore (`firestore.get` / `firestore.exists`) to tie
// every object to the attempt doc it belongs to, so this suite needs BOTH
// emulators up: `firebase emulators:exec --only firestore,storage` (see the
// `test:rules` / `test:storage-rules` scripts in package.json).
const projectId = "demo-hitrate-rules";
const teamId = "3DDA7E8A-091D-4B62-A0AA-56DB2521E300";
const ownerId = "owner-uid";
const memberAId = "member-a-uid";
const memberBId = "member-b-uid";
const strangerId = "stranger-uid";
const attemptId = "4F0C2B6E-0E9A-4C1D-9A3B-7E5D2F1A0B9C";
const framesPath = `teams/${teamId}/stunts/${attemptId}/frames.json`;
const clipPath = `teams/${teamId}/stunts/${attemptId}/clip.mov`;
const tumbleId = "C934B11A-6290-4F1E-8EF5-C86DF630F145";
const tumblePath = `teams/${teamId}/tumbles/${tumbleId}/analysis.json`;

const clipBytes = new Uint8Array([0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70]);

let testEnv;

function storageFor(uid) {
  return testEnv.authenticatedContext(uid).storage();
}

function upload(uid, path, contentType = "application/json") {
  return uploadBytes(ref(storageFor(uid), path), clipBytes, { contentType });
}

describe("HitRate Storage rules — StuntScope stunt stats", () => {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: await readFile(new URL("../firestore.rules", import.meta.url), "utf8"),
      },
      storage: {
        rules: await readFile(new URL("../storage.rules", import.meta.url), "utf8"),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.clearStorage();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "teams", teamId), {
        name: "Senior Coed",
        ownerUID: ownerId,
        memberIds: [memberAId, memberBId],
        joinCode: "ABC234",
        updatedAt: new Date("2026-10-23T00:00:00Z"),
      });
      // The rep the stats belong to — written FIRST, by member A.
      await setDoc(doc(db, "teams", teamId, "attempts", attemptId), {
        teamId,
        groupId: "0B0F2A56-9F4D-4B23-9B5B-2D30F0E7A111",
        outcomeRaw: 0,
        timestamp: new Date("2026-10-23T18:00:00Z"),
        loggerId: memberAId,
        source: "stuntscope",
        onBasePercent: 82,
        updatedAt: new Date("2026-10-23T18:00:00Z"),
      });
      await setDoc(doc(db, "teams", teamId, "tumbles", tumbleId), {
        teamId,
        loggerId: memberAId,
        ready: false,
        storagePath: tumblePath,
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  it("lets the member who logged the attempt upload its per-frame JSON", async () => {
    await assertSucceeds(upload(memberAId, framesPath));
  });

  it("denies any video upload, even from the logger (stats only)", async () => {
    await assertFails(upload(memberAId, clipPath, "video/quicktime"));
    await assertFails(upload(memberAId, framesPath, "video/quicktime"));
    await assertFails(upload(memberAId, `teams/${teamId}/stunts/${attemptId}/clip.json`));
  });

  it("denies another member uploading under that attempt", async () => {
    await assertFails(upload(memberBId, framesPath));
  });

  it("denies the folder owner uploading under a member's attempt", async () => {
    await assertFails(upload(ownerId, framesPath));
  });

  it("denies an upload for an attempt doc that doesn't exist yet", async () => {
    const orphan = `teams/${teamId}/stunts/NO-SUCH-ATTEMPT/frames.json`;
    await assertFails(upload(memberAId, orphan));
    await assertFails(upload(ownerId, orphan));
  });

  it("denies a wrong content type even from the logger", async () => {
    await assertFails(upload(memberAId, framesPath, "application/octet-stream"));
    await assertFails(upload(memberAId, framesPath, "text/html"));
  });

  it("lets any folder member read the per-frame JSON", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(ref(context.storage(), framesPath), clipBytes,
        { contentType: "application/json" });
    });
    await assertSucceeds(getBytes(ref(storageFor(memberBId), framesPath)));
    await assertSucceeds(getBytes(ref(storageFor(ownerId), framesPath)));
  });

  it("denies a non-member reading the per-frame JSON", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(ref(context.storage(), framesPath), clipBytes,
        { contentType: "application/json" });
    });
    await assertFails(getBytes(ref(storageFor(strangerId), framesPath)));
    await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), framesPath)));
  });

  it("denies a non-member uploading even when the attempt exists", async () => {
    await assertFails(upload(strangerId, framesPath));
  });

  it("denies anything outside the stunts tree", async () => {
    await assertFails(upload(memberAId, `teams/${teamId}/avatar.png`, "image/png"));
    await assertFails(upload(ownerId, "loose/clip.mov"));
  });

  it("lets the logger upload tumble JSON and the team read it", async () => {
    await assertSucceeds(upload(memberAId, tumblePath, "application/json"));
    await assertSucceeds(getBytes(ref(storageFor(memberBId), tumblePath)));
  });

  it("denies another member or a wrong type for tumble data", async () => {
    await assertFails(upload(memberBId, tumblePath, "application/json"));
    await assertFails(upload(memberAId, tumblePath, "text/plain"));
    await assertFails(getBytes(ref(storageFor(strangerId), tumblePath)));
  });
});
