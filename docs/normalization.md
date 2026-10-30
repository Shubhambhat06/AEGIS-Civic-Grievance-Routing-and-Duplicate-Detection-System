# Normalization analysis

**AEGIS — DBMS Level 3 Project**

This document works through the functional dependencies of every relation in the AEGIS schema and shows which normal form each one reaches. It maps onto Unit 3 of the syllabus: *Functional Dependencies, Inference Rules, Normal Forms Based on Primary Keys (1NF, 2NF, 3NF), General Definitions of Second and Third Normal Forms, Boyce-Codd Normal Form*.

**Result: all 11 relations are in BCNF**, with one deliberate, documented denormalization that is not a normal-form violation (section 5).

---

## 1. Notation

- `A → B` means A functionally determines B.
- Underlined attributes form the primary key.
- A relation is in **1NF** if every attribute is atomic and there are no repeating groups.
- **2NF** = 1NF + no non-prime attribute is partially dependent on a candidate key (only matters when the key is composite).
- **3NF** = 2NF + no transitive dependency of a non-prime attribute on a candidate key.
- **BCNF** = for every non-trivial `X → Y`, X is a superkey.

---

## 2. Relation-by-relation analysis

### 2.1 `ward(ward_id, ward_name, zone)`

**Functional dependencies**

```
ward_id   → ward_name, zone
ward_name → ward_id, zone          (ward_name is UNIQUE)
```

**Candidate keys:** `{ward_id}`, `{ward_name}`

Both determinants are candidate keys, so every non-trivial FD has a superkey on the left.

One point worth defending in a viva: is `ward_name → zone` a transitive dependency that breaks 3NF? No. `ward_name` is itself a candidate key (it carries a `UNIQUE` constraint), so `zone` depends on a key, not on a non-prime attribute. Transitivity requires the intermediate attribute to be non-prime, and here it is prime.

**→ BCNF.**

---

### 2.2 `citizen(citizen_id, email, full_name, password_hash, ward_id, created_at)`

**Functional dependencies**

```
citizen_id → email, full_name, password_hash, ward_id, created_at
email      → citizen_id, full_name, password_hash, ward_id, created_at   (email is UNIQUE)
```

**Candidate keys:** `{citizen_id}`, `{email}`

The key is simple, so 2NF is automatic — a partial dependency needs a composite key.

There is no transitive dependency. In particular `ward_id → zone` is *not* an FD of this relation, because `zone` is not an attribute of `citizen`. Had we denormalized by copying `zone` into `citizen`, we would have created exactly the 3NF violation `citizen_id → ward_id → zone`. Keeping ward attributes in `ward` and referencing them by foreign key is what avoids it.

**→ BCNF.**

---

### 2.3 `citizen_phone(citizen_id, phone)`

**Functional dependencies**

```
(none beyond the trivial)
```

**Candidate key:** `{citizen_id, phone}` — the whole relation is the key.

This relation exists *because of* normalization. In the ER model `phone` is a multivalued attribute of `CITIZEN`. Had we stored several numbers in one `citizen.phone` column — `'9845012301, 08023456789'` — that column would not be atomic and the design would fail **1NF**. Had we instead added `phone1`, `phone2`, `phone3` columns, that is a repeating group, which also fails 1NF and additionally caps how many numbers a citizen may have.

The standard mapping rule — a multivalued attribute becomes its own relation keyed by the owner's key plus the attribute — produces a relation that is in 1NF, and since there are no non-key attributes at all, trivially in BCNF.

**→ BCNF.** (And the reason 1NF holds for `citizen` at all.)

---

### 2.4 `department(dept_id, dept_name, category, default_sla_hours)`

**Functional dependencies**

```
dept_id   → dept_name, category, default_sla_hours
dept_name → dept_id, category, default_sla_hours    (dept_name is UNIQUE)
```

**Candidate keys:** `{dept_id}`, `{dept_name}`

Note what is deliberately *not* an FD here: `category → default_sla_hours`. Two departments in the same category may have different SLA policies, and the schema allows that. If we had decided that the SLA is a property of the category rather than the department, then `category → default_sla_hours` would hold, `category` would not be a superkey, and the relation would drop out of BCNF — we would then have to split off a `category(category, default_sla_hours)` relation.

**→ BCNF.**

---

### 2.5 `staff(staff_id, email, full_name, password_hash, role, dept_id)`

**Functional dependencies**

```
staff_id → email, full_name, password_hash, role, dept_id
email    → staff_id, full_name, password_hash, role, dept_id   (email is UNIQUE)
```

**Candidate keys:** `{staff_id}`, `{email}`

`dept_name` is deliberately absent. Storing it here would create `staff_id → dept_id → dept_name`, a textbook transitive dependency and a 3NF violation, and renaming a department would then require updating every staff row.

**→ BCNF.**

---

### 2.6 `complaint(complaint_id, citizen_id, dept_id, ward_id, assigned_staff_id, title, description, status, priority, latitude, longitude, filed_at, sla_deadline, resolved_at, duplicate_count, search_tsv)`

**Functional dependencies**

```
complaint_id → every other attribute
```

**Candidate key:** `{complaint_id}` (only one)

Simple key, so 2NF holds automatically.

Three dependencies that might look like they exist, and why they do not:

**`ward_id → zone`?** Not an FD of this relation — `zone` lives in `ward`. We store only the foreign key.

**`dept_id → sla_deadline`?** This is the interesting one, and the answer is deliberate. If `sla_deadline` were computed as *filing time + the department's current SLA hours*, then `(dept_id, filed_at) → sla_deadline` would hold, and since `(dept_id, filed_at)` is not a superkey, the relation would violate BCNF.

It is not an FD because `sla_deadline` is a **snapshot taken at filing time**, not a derived value. If a department later changes `default_sla_hours` from 72 to 48, existing complaints keep the deadline they were given. Two complaints in the same department filed at the same instant can therefore have different deadlines if the policy changed between them. The value is independent data, not a function of `dept_id`.

This is a case where a *business* requirement (historical SLA figures must not be retroactively rewritten) and the *normalization* requirement point the same way.

**`search_tsv`?** This is a generated column — `complaint_id → title, description → search_tsv`, which looks transitive. Strictly, a stored generated column is derived data and normalization theory treats the relation as if it were not there; PostgreSQL guarantees it cannot drift from `title` and `description` because it is recomputed on every write and cannot be set directly. The update anomaly that 3NF exists to prevent is therefore impossible by construction.

**→ BCNF** (treating `search_tsv` as a materialized index structure rather than a data attribute).

---

### 2.7 `complaint_attachment(complaint_id, attachment_url)`

**Candidate key:** `{complaint_id, attachment_url}` — the whole relation.

Same story as `citizen_phone`: this relation exists to keep `complaint` in 1NF, since `attachment_url` is a multivalued attribute in the ER model. No non-key attributes.

**→ BCNF.**

---

### 2.8 `complaint_embedding(complaint_id, embedding, model_name, generated_at)`

**Functional dependencies**

```
complaint_id → embedding, model_name, generated_at
```

**Candidate key:** `{complaint_id}`

Is `embedding → model_name` an FD? No. Two different models could in principle produce the same vector, and more importantly the same model produces many different vectors, so `embedding` determines nothing. The only determinant is the key.

Note this relation is in BCNF *and* separate from `complaint` for reasons that have nothing to do with normalization — the 1:1 split is a physical-design decision (the embedding arrives later, and is large). Normalization does not require the split; it simply does not forbid it.

**→ BCNF.**

---

### 2.9 `duplicate_link(child_complaint_id, parent_complaint_id, similarity_score, merged_at, merged_by)`

**Functional dependencies**

```
child_complaint_id → parent_complaint_id, similarity_score, merged_at, merged_by
```

**Candidate key:** `{child_complaint_id}`

The key is `child_complaint_id` alone, not the pair, because a complaint can be merged into at most one parent. That is a real business rule and the primary key enforces it — making the key `(child, parent)` would silently permit one complaint to be merged into two different parents.

`similarity_score` depends on the pair of complaints, and since `child_complaint_id` determines `parent_complaint_id`, it is functionally dependent on the key by transitivity through a *prime* attribute. No violation.

**→ BCNF.**

---

### 2.10 `status_history(complaint_id, changed_at, old_status, new_status, changed_by, remarks)`

**Functional dependencies**

```
(complaint_id, changed_at) → old_status, new_status, changed_by, remarks
```

**Candidate key:** `{complaint_id, changed_at}` — composite, so 2NF must actually be checked.

**Is there a partial dependency?** Does `complaint_id` alone determine any non-prime attribute? No — one complaint has many history rows with different statuses. Does `changed_at` alone determine anything? No — two different complaints can change status at different times with no relationship. Every non-prime attribute needs both halves of the key.

**→ 2NF holds.** No transitive dependencies among the non-prime attributes either.

**→ BCNF.**

This is the one relation in the schema where the 2NF check is not vacuous, which makes it the one worth being asked about.

---

### 2.11 `feedback(complaint_id, submitted_at, rating, comments)`

**Functional dependencies**

```
complaint_id → submitted_at, rating, comments
```

**Candidate key:** `{complaint_id}`

A complaint receives at most one feedback record, so `complaint_id` alone is the key and `submitted_at` is an ordinary attribute rather than part of it. (Contrast `status_history`, where the timestamp *is* part of the key because there are many rows per complaint.)

**→ BCNF.**

---

## 3. Summary table

| Relation | Candidate keys | Composite key? | Highest normal form |
|---|---|---|---|
| `ward` | `{ward_id}`, `{ward_name}` | no | BCNF |
| `citizen` | `{citizen_id}`, `{email}` | no | BCNF |
| `citizen_phone` | `{citizen_id, phone}` | yes (all-key) | BCNF |
| `department` | `{dept_id}`, `{dept_name}` | no | BCNF |
| `staff` | `{staff_id}`, `{email}` | no | BCNF |
| `complaint` | `{complaint_id}` | no | BCNF |
| `complaint_attachment` | `{complaint_id, attachment_url}` | yes (all-key) | BCNF |
| `complaint_embedding` | `{complaint_id}` | no | BCNF |
| `duplicate_link` | `{child_complaint_id}` | no | BCNF |
| `status_history` | `{complaint_id, changed_at}` | yes | BCNF |
| `feedback` | `{complaint_id}` | no | BCNF |

---

## 4. Higher normal forms

**4NF** concerns multivalued dependencies. The two candidates in this schema were `phone` and `attachment_url`, and both were already split into their own relations during ER-to-relational mapping, which is exactly the decomposition 4NF would require. Had we put both into one table — `citizen_contact(citizen_id, phone, address)` — we would have had two independent multivalued dependencies on the same key and a genuine 4NF violation producing a cartesian product of rows. We do not.

**5NF** concerns join dependencies that are not implied by candidate keys. No relation here is decomposable into three or more projections that rejoin losslessly, so 5NF holds trivially.

---

## 5. The one deliberate denormalization

`complaint.duplicate_count` stores a value that could be computed:

```sql
SELECT COUNT(*) FROM duplicate_link WHERE parent_complaint_id = c.complaint_id
```

**Is this a normal-form violation?** No, and this distinction matters. Normalization is about functional dependencies *among attributes of a relation*. `duplicate_count` is determined by `complaint_id`, which is the key, so no normal form is broken. What it introduces is a **redundancy across relations** — the same fact is recorded in two places — which risks an update anomaly if the two ever disagree.

**Why we accepted it.** Rendering the staff queue would otherwise need a correlated subquery or a join plus aggregate per row. The counter turns that into a plain column read.

**How the risk is controlled.**

1. The counter is only ever changed inside `fn_merge_duplicate`, in the same transaction that inserts the `duplicate_link` row. They cannot drift apart because they are never written separately.
2. Test **T3.2** asserts the stored counter equals the real link count.
3. Test **T3.5** forces a merge to fail midway and asserts the counter is unchanged, proving the rollback covers both writes.
4. `scripts/audit.py` check **F5** re-verifies the invariant across the whole table on every run.

If any of those four fail, the denormalization has broken and the stored column is wrong. That is the standard justification for a controlled denormalization: it is permitted when the redundancy is maintained atomically and continuously verified, rather than being permitted because it is convenient.

---

## 6. Lossless-join and dependency preservation

The schema was produced by ER-to-relational mapping, not by decomposing a single universal relation, so there is no decomposition to verify in the usual sense. Nevertheless the two decompositions that *did* happen are both well behaved:

| Decomposition | Lossless? | Dependencies preserved? |
|---|---|---|
| `citizen` split from `citizen_phone` | Yes — they share `citizen_id`, a key of `citizen` | Yes |
| `complaint` split from `complaint_embedding` | Yes — they share `complaint_id`, a key of both | Yes |

A decomposition is lossless when the shared attribute is a superkey of at least one of the resulting relations. In both cases the shared attribute is the full primary key of both sides, so rejoining recovers the original relation exactly, with no spurious tuples.
