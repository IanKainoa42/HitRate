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
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";

const projectId = "demo-hitrate-rules";
const teamId = "3DDA7E8A-091D-4B62-A0AA-56DB2521E300";
const joinCode = "ABC234";
const ownerId = "owner-uid";
const memberAId = "member-a-uid";
const memberBId = "member-b-uid";
const joiningId = "joining-uid";
const assignmentId = "5C1B9E44-7A21-4D6E-9C10-9F0B3A2E7C55";

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
      await setDoc(doc(db, "teams", teamId, "sessions", "member-session"), {
        teamId,
        loggerId: memberBId,
        startedAt: new Date("2026-08-11T00:00:00Z"),
        updatedAt: new Date("2026-08-11T00:01:00Z"),
      });
      await setDoc(doc(db, "teams", teamId, "attempts", "member-attempt"), {
        teamId,
        loggerId: memberBId,
        outcomeRaw: 0,
        timestamp: new Date("2026-08-11T00:01:00Z"),
        updatedAt: new Date("2026-08-11T00:01:00Z"),
      });
      await setDoc(doc(db, "teams", teamId, "assignments", assignmentId), {
        teamId,
        groupId: "0B0F2A56-9F4D-4B23-9B5B-2D30F0E7A111",
        targetReps: 50,
        note: "chest up out of the set",
        subjectIdsRaw: "",
        startedAt: new Date("2026-08-11T00:00:00Z"),
        createdBy: ownerId,
        updatedAt: new Date("2026-08-11T00:00:00Z"),
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  it("allows the owner to remove access without deleting the member's history", async () => {
    const db = firestoreFor(ownerId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: [memberAId],
      updatedAt: serverTimestamp(),
    }));

    const session = await getDoc(doc(db, "teams", teamId, "sessions", "member-session"));
    const attempt = await getDoc(doc(db, "teams", teamId, "attempts", "member-attempt"));
    assert.equal(session.exists(), true);
    assert.equal(session.data().loggerId, memberBId);
    assert.equal(attempt.exists(), true);
    assert.equal(attempt.data().loggerId, memberBId);
  });

  it("lets an athlete read the homework assigned to them", async () => {
    const db = firestoreFor(memberAId);
    const assignment = await getDoc(doc(db, "teams", teamId, "assignments", assignmentId));
    assert.equal(assignment.exists(), true);
    assert.equal(assignment.data().targetReps, 50);
  });

  it("lets the coach assign homework", async () => {
    const db = firestoreFor(ownerId);
    await assertSucceeds(setDoc(doc(db, "teams", teamId, "assignments", "new-assignment"), {
      teamId,
      groupId: "0B0F2A56-9F4D-4B23-9B5B-2D30F0E7A111",
      targetReps: 100,
      note: "",
      subjectIdsRaw: "",
      startedAt: new Date("2026-08-18T00:00:00Z"),
      createdBy: ownerId,
      updatedAt: new Date("2026-08-18T00:00:00Z"),
    }));
  });

  it("denies an athlete lowering their own rep target", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(doc(db, "teams", teamId, "assignments", assignmentId), {
      targetReps: 1,
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies an athlete deleting their homework", async () => {
    const db = firestoreFor(memberAId);
    await assertFails(deleteDoc(doc(db, "teams", teamId, "assignments", assignmentId)));
  });

  it("denies a nonmember reading the folder's homework", async () => {
    const db = firestoreFor(joiningId);
    await assertFails(getDoc(doc(db, "teams", teamId, "assignments", assignmentId)));
  });

  it("allows a signed-in user to resolve one exact join code", async () => {
    const db = firestoreFor("joining-uid");
    await assertSucceeds(getDoc(doc(db, "joinCodes", joinCode)));
  });

  it("rejects publishing a join code before its target folder exists", async () => {
    const db = firestoreFor(ownerId);
    await assertFails(setDoc(doc(db, "joinCodes", "ORPHAN"), {
      teamId: "7E0B08CC-5FD1-4997-99B2-417488D4A5B8",
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
    }));
  });

  it("allows an owner to atomically publish a new folder and its join code", async () => {
    const db = firestoreFor(ownerId);
    const newTeamId = "0AEBAD89-28B8-48B5-94C0-1F7C71D23E97";
    const newCode = "NEW234";
    const batch = writeBatch(db);
    batch.set(doc(db, "teams", newTeamId), {
      name: "Fresh folder",
      ownerUID: ownerId,
      memberIds: [],
      joinCode: newCode,
      updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, "joinCodes", newCode), {
      teamId: newTeamId,
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
  });

  it("rejects retargeting a code to a folder owned by someone else", async () => {
    const db = firestoreFor(ownerId);
    const otherTeamId = "8CF73377-A560-441C-83DA-FC13C8C02B51";
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "teams", otherTeamId), {
        name: "Someone else's folder",
        ownerUID: memberAId,
        memberIds: [],
        updatedAt: new Date("2026-08-20T00:00:00Z"),
      });
    });

    await assertFails(setDoc(doc(db, "joinCodes", joinCode), {
      teamId: otherTeamId,
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
    }, { merge: true }));
  });

  it("rejects retargeting a code even to another folder owned by the same owner", async () => {
    const db = firestoreFor(ownerId);
    const otherTeamId = "B49A41F3-67DE-4E72-A240-B23CBF182980";
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "teams", otherTeamId), {
        name: "Owner's other folder",
        ownerUID: ownerId,
        memberIds: [],
        updatedAt: new Date("2026-08-20T00:00:00Z"),
      });
    });

    await assertFails(setDoc(doc(db, "joinCodes", joinCode), {
      teamId: otherTeamId,
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
    }, { merge: true }));
  });

  it("allows a released client to publish a code for an existing folder", async () => {
    const db = firestoreFor(ownerId);
    const codeRef = doc(db, "joinCodes", "OLD234");
    const collisionCheck = await assertSucceeds(getDoc(codeRef));
    assert.equal(collisionCheck.exists(), false);
    await assertSucceeds(setDoc(codeRef, {
      teamId,
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
    }, { merge: true }));
  });

  it("denies an owner changing a folder's owner uid", async () => {
    const db = firestoreFor(ownerId);
    await assertFails(updateDoc(teamRef(db), {
      ownerUID: memberAId,
      updatedAt: serverTimestamp(),
    }));
  });

  it("denies listing the join-code directory", async () => {
    const db = firestoreFor("joining-uid");
    await assertFails(getDocs(collection(db, "joinCodes")));
  });

  it("allows a nonmember to add only their own uid", async () => {
    const db = firestoreFor(joiningId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: arrayUnion(joiningId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("rejects a join code whose folder has been deleted", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(teamRef(context.firestore()), {
        deletedAt: new Date("2026-08-12T00:00:00Z"),
      });
    });

    const db = firestoreFor(joiningId);
    await assertFails(getDoc(doc(db, "joinCodes", joinCode)));
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayUnion(joiningId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("still lets an existing member leave a deleted folder", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(teamRef(context.firestore()), {
        deletedAt: new Date("2026-08-12T00:00:00Z"),
      });
    });

    const db = firestoreFor(memberAId);
    await assertSucceeds(updateDoc(teamRef(db), {
      memberIds: arrayRemove(memberAId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("rejects an existing member reusing a deleted folder's code", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(teamRef(context.firestore()), {
        deletedAt: new Date("2026-08-12T00:00:00Z"),
      });
    });

    const db = firestoreFor(memberAId);
    await assertFails(updateDoc(teamRef(db), {
      memberIds: arrayUnion(memberAId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("rejects a join code whose folder document is missing", async () => {
    const staleCode = "STALE2";
    const missingTeamId = "7E0B08CC-5FD1-4997-99B2-417488D4A5B8";
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "joinCodes", staleCode), {
        teamId: missingTeamId,
        ownerUID: ownerId,
        createdAt: new Date("2026-08-11T00:00:00Z"),
      });
    });

    const db = firestoreFor(joiningId);
    await assertFails(getDoc(doc(db, "joinCodes", staleCode)));
    await assertFails(updateDoc(doc(db, "teams", missingTeamId), {
      memberIds: arrayUnion(joiningId),
      updatedAt: serverTimestamp(),
    }));
  });

  it("rejects publishing a new code for a deleted folder", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(teamRef(context.firestore()), {
        deletedAt: new Date("2026-08-12T00:00:00Z"),
      });
    });

    const db = firestoreFor(ownerId);
    await assertFails(setDoc(doc(db, "joinCodes", "DEAD23"), {
      teamId,
      ownerUID: ownerId,
      createdAt: serverTimestamp(),
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
