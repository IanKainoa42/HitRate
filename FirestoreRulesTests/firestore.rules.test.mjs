import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "demo-hitrate-rules";
const teamId = "3DDA7E8A-091D-4B62-A0AA-56DB2521E300";
const joinCode = "ABC234";
const ownerId = "owner-uid";
const memberAId = "member-a-uid";
const memberBId = "member-b-uid";

let testEnv;

function firestoreFor(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function teamRef(db) {
  return doc(db, "teams", teamId);
}

describe("HitRate Firestore team authorization", () => {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: await readFile(new URL("../firestore.rules", import.meta.url), "utf8"),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(teamRef(db), {
        name: "Senior Coed",
        ownerUID: ownerId,
        memberIds: [memberAId, memberBId],
        joinCode,
        updatedAt: new Date("2026-08-11T00:00:00Z"),
      });
      await setDoc(doc(db, "joinCodes", joinCode), {
        teamId,
        ownerUID: ownerId,
        createdAt: new Date("2026-08-11T00:00:00Z"),
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  it("allows the owner to administer the membership list", async () => {
    const db = firestoreFor(ownerId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: [memberAId],
      updatedAt: serverTimestamp(),
    }));
  });

  it("allows a signed-in user to resolve one exact join code", async () => {
    const db = firestoreFor("joining-uid");
    await assertSucceeds(getDoc(doc(db, "joinCodes", joinCode)));
  });

  it("denies listing the join-code directory", async () => {
    const db = firestoreFor("joining-uid");
    await assertFails(getDocs(collection(db, "joinCodes")));
  });

  it("allows a nonmember to add only their own uid", async () => {
    const uid = "joining-uid";
    const db = firestoreFor(uid);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: arrayUnion(uid),
      updatedAt: serverTimestamp(),
    }));
  });

  it("allows a member to remove only their own uid", async () => {
    const db = firestoreFor(memberAId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberAId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("allows an existing member to redeem the same code idempotently", async () => {
    const db = firestoreFor(memberAId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: arrayUnion(memberAId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("allows self-leave even if an old roster already contains duplicates", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(teamRef(context.firestore()), {
        memberIds: [memberAId, memberBId, memberBId],
      });
    });

    const memberADb = firestoreFor(memberAId);
    await assertSucceeds(updateDoc(teamRef(memberADb), {
      memberIds: arrayRemove(memberAId),
      updatedAt: serverTimestamp(),
    }));

    const survivingMemberSnapshot = await getDoc(teamRef(firestoreFor(memberBId)));
    assert.deepEqual(survivingMemberSnapshot.data().memberIds, [memberBId, memberBId]);
  });

  it("denies an arbitrary timestamp on an otherwise valid self-leave", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberAId),
      updatedAt: new Date("2099-01-01T00:00:00Z"),
    }));
  });

  it("denies changing updatedAt to a non-timestamp value", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberAId),
      updatedAt: "poisoned",
    }));
  });

  it("denies deleting updatedAt during a membership change", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberAId),
      updatedAt: deleteField(),
    }));
  });

  it("denies a nonmember adding another uid", async () => {
    const db = firestoreFor("attacker-uid");
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayUnion("accomplice-uid"),
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies a member granting access to another uid", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayUnion("accomplice-uid"),
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies a member ejecting another member", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberBId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies self-joining while ejecting an existing member", async () => {
    const uid = "attacker-uid";
    const db = firestoreFor(uid);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: [memberAId, uid],
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies duplicate membership entries", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: [memberAId, memberBId, memberBId],
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies a member changing team metadata", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      name: "Hijacked",
      memberIds: arrayRemove(memberAId),
      updatedAt: serverTimestamp(),
    }));
  });
});
