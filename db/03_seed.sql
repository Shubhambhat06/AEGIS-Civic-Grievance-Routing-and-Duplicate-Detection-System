-- =====================================================================
-- AEGIS - File 3 of 5 : SEED DATA (DML - INSERT)
--
-- Loads a small but realistic dataset:
--   6 wards, 6 departments, 8 staff, 10 citizens,
--   14 historical resolved complaints (so routing has something to
--   learn from) and 10 new complaints including deliberate duplicates.
--
-- Run as: psql -U postgres -d aegis -f db/03_seed.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- DEMO EMBEDDING HELPER
--
-- In production, scripts/embed.py fills complaint_embedding using the
-- all-MiniLM-L6-v2 sentence-transformer model.
--
-- So that the project can also be demonstrated with nothing but psql,
-- this function produces a 384-dimension embedding using the classic
-- "hashing trick": each word is hashed to one of 384 buckets and the
-- resulting count vector is L2-normalised. It is a genuine (if simple)
-- text embedding - documents sharing many words end up close together
-- under cosine distance - which is enough to demonstrate duplicate
-- detection end to end.
--
-- Replace the vectors it produces by running scripts/embed.py when the
-- real model is available.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_demo_embedding(p_text TEXT)
RETURNS VECTOR(384)
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    v_dim   CONSTANT INT := 384;
    v_arr   FLOAT8[];
    v_tok   TEXT;
    v_idx   INT;
    v_norm  FLOAT8 := 0;
    i       INT;
BEGIN
    -- start with a vector of zeros
    v_arr := array_fill(0::FLOAT8, ARRAY[v_dim]);

    -- one bucket increment per word, ignoring very short words
    FOR v_tok IN
        SELECT t FROM regexp_split_to_table(lower(p_text), '[^a-z0-9]+') AS t
        WHERE length(t) > 2
    LOOP
        v_idx := (abs(hashtext(v_tok)) % v_dim) + 1;
        v_arr[v_idx] := v_arr[v_idx] + 1;
    END LOOP;

    -- L2-normalise so cosine distance behaves sensibly
    FOR i IN 1..v_dim LOOP
        v_norm := v_norm + v_arr[i] * v_arr[i];
    END LOOP;

    IF v_norm > 0 THEN
        v_norm := sqrt(v_norm);
        FOR i IN 1..v_dim LOOP
            v_arr[i] := v_arr[i] / v_norm;
        END LOOP;
    ELSE
        -- empty text: return a fixed non-zero vector so the NOT NULL
        -- column still gets a valid value
        v_arr[1] := 1;
    END IF;

    -- Cast the array straight to a vector. Going through ::TEXT would
    -- produce Postgres array syntax {..}, which pgvector rejects: its
    -- text format is [..].
    RETURN v_arr::VECTOR(384);
END;
$$;


-- ---------------------------------------------------------------------
-- 1. WARDS
-- ---------------------------------------------------------------------
INSERT INTO ward (ward_name, zone) VALUES
    ('Basaveshwaranagar', 'West'),
    ('Rajajinagar',       'West'),
    ('Malleshwaram',      'North'),
    ('Indiranagar',       'East'),
    ('Jayanagar',         'South'),
    ('Koramangala',       'South');


-- ---------------------------------------------------------------------
-- 2. DEPARTMENTS
--    default_sla_hours reflects how urgent each category usually is.
-- ---------------------------------------------------------------------
INSERT INTO department (dept_name, category, default_sla_hours) VALUES
    ('Roads and Infrastructure', 'Roads',       72),
    ('Water Supply',             'Utilities',   24),
    ('Solid Waste Management',   'Sanitation',  48),
    ('Street Lighting',          'Electrical',  48),
    ('Parks and Horticulture',   'Environment', 120),
    ('Stormwater Drains',        'Drainage',    36);


-- ---------------------------------------------------------------------
-- 3. STAFF
--    All seeded accounts use the password 'password123'. The value
--    stored is its bcrypt hash - change these before any real use.
--    Real deployments create accounts through the application, which
--    hashes the password before it ever reaches the database.
-- ---------------------------------------------------------------------
INSERT INTO staff (email, full_name, password_hash, role, dept_id) VALUES
    ('admin@aegis.example',    'Priya Raghavan',  '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'ADMIN', 1),
    ('roads1@aegis.example',   'Mahesh Kumar',    '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 1),
    ('roads2@aegis.example',   'Anita Desai',     '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 1),
    ('water1@aegis.example',   'Ravi Shankar',    '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 2),
    ('waste1@aegis.example',   'Fatima Sheikh',   '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 3),
    ('light1@aegis.example',   'Joseph Mathew',   '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 4),
    ('parks1@aegis.example',   'Lakshmi Iyer',    '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 5),
    ('drains1@aegis.example',  'Suresh Gowda',    '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 'STAFF', 6);


-- ---------------------------------------------------------------------
-- 4. CITIZENS
-- ---------------------------------------------------------------------
INSERT INTO citizen (email, full_name, password_hash, ward_id) VALUES
    ('arjun.menon@example.com',  'Arjun Menon',     '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 1),
    ('divya.rao@example.com',    'Divya Rao',       '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 1),
    ('karthik.s@example.com',    'Karthik Subbu',   '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 1),
    ('meera.nair@example.com',   'Meera Nair',      '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 2),
    ('rahul.verma@example.com',  'Rahul Verma',     '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 2),
    ('sneha.p@example.com',      'Sneha Prakash',   '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 3),
    ('vikram.j@example.com',     'Vikram Joshi',    '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 4),
    ('nandini.k@example.com',    'Nandini Kulkarni','$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 4),
    ('farhan.ali@example.com',   'Farhan Ali',      '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 5),
    ('tanvi.shah@example.com',   'Tanvi Shah',      '$2a$10$7MY5QZUxQwqgx/Jo1Xhdce8VR4x56U6sPD6ibsFPh8ik.jtFdwOxy', 6);


-- ---------------------------------------------------------------------
-- 5. CITIZEN PHONE NUMBERS (the multivalued attribute)
-- ---------------------------------------------------------------------
INSERT INTO citizen_phone (citizen_id, phone) VALUES
    (1, '9845012301'), (1, '08023456789'),   -- Arjun has mobile + landline
    (2, '9845012302'),
    (3, '9845012303'),
    (4, '9845012304'),
    (5, '9845012305'),
    (6, '9845012306'),
    (7, '9845012307'),
    (8, '9845012308'),
    (9, '9845012309'),
    (10,'9845012310');


-- ---------------------------------------------------------------------
-- 6. HISTORICAL RESOLVED COMPLAINTS
--
--    These give fn_route_complaint something to learn from: each one
--    already carries the department that actually resolved it.
--
--    Resolution times are deliberately mixed: Water Supply, Street
--    Lighting and Stormwater Drains resolve inside their SLA, while
--    Roads, Solid Waste and Parks overrun it. That gives the admin
--    dashboard's "time to resolve against target" chart a real contrast.
--    They are inserted with explicit dates in the past.
-- ---------------------------------------------------------------------
INSERT INTO complaint
    (citizen_id, dept_id, ward_id, assigned_staff_id, title, description,
     status, priority, filed_at, sla_deadline, resolved_at)
VALUES
-- Roads (dept 1)
 (1, 1, 1, 2, 'Large pothole on 2nd Main Road',
  'There is a deep pothole on 2nd Main Road near the bus stop. Two-wheelers are swerving to avoid it and it is dangerous during rain.',
  'RESOLVED', 'HIGH',   now() - interval '90 days', now() - interval '87 days', now() - interval '86 days'),
 (4, 1, 2, 3, 'Road surface broken near market',
  'The road surface outside the vegetable market has broken up completely. Loose gravel everywhere and vehicles are skidding.',
  'RESOLVED', 'MEDIUM', now() - interval '85 days', now() - interval '82 days', now() - interval '80 days'),
 (7, 1, 4, 2, 'Sunken patch on service road',
  'A sunken patch has formed on the service road. It collects water and the asphalt around it keeps crumbling further.',
  'RESOLVED', 'MEDIUM', now() - interval '70 days', now() - interval '67 days', now() - interval '66 days'),

-- Water Supply (dept 2)
 (2, 2, 1, 4, 'No water supply for three days',
  'Our building has had no water supply from the municipal line for three days now. Tanker deliveries are not keeping up.',
  'RESOLVED', 'CRITICAL', now() - interval '80 days', now() - interval '79 days', now() - interval '79 days 18 hours'),
 (5, 2, 2, 4, 'Pipeline leak flooding the street',
  'A municipal water pipeline is leaking continuously and flooding the street. Large volume of drinking water is being wasted.',
  'RESOLVED', 'HIGH',     now() - interval '75 days', now() - interval '74 days', now() - interval '74 days 20 hours'),
 (9, 2, 5, 4, 'Low water pressure in the whole lane',
  'Water pressure has dropped so low that it does not reach the overhead tank. The entire lane is affected, not just us.',
  'RESOLVED', 'MEDIUM',   now() - interval '60 days', now() - interval '59 days', now() - interval '59 days 8 hours'),

-- Solid Waste (dept 3)
 (3, 3, 1, 5, 'Garbage not collected for a week',
  'The garbage collection vehicle has not come to our street for a week. Waste is piling up at the corner and smells terrible.',
  'RESOLVED', 'HIGH',   now() - interval '65 days', now() - interval '63 days', now() - interval '62 days'),
 (6, 3, 3, 5, 'Illegal dumping on empty plot',
  'People are dumping construction debris and household waste on the empty plot behind our house every night.',
  'RESOLVED', 'MEDIUM', now() - interval '55 days', now() - interval '53 days', now() - interval '51 days'),

-- Street Lighting (dept 4)
 (8, 4, 4, 6, 'Street light not working near park',
  'The street light near the park entrance has not been working for two weeks. The stretch is completely dark at night.',
  'RESOLVED', 'MEDIUM', now() - interval '50 days', now() - interval '48 days', now() - interval '49 days'),
 (10,4, 6, 6, 'Flickering street lamp whole night',
  'A street lamp on our road flickers continuously the whole night. It is both annoying and clearly faulty wiring.',
  'RESOLVED', 'LOW',    now() - interval '45 days', now() - interval '43 days', now() - interval '44 days 6 hours'),

-- Parks (dept 5)
 (6, 5, 3, 7, 'Overgrown trees blocking footpath',
  'Tree branches have grown so low over the footpath that pedestrians have to step onto the road to get past.',
  'RESOLVED', 'LOW',    now() - interval '40 days', now() - interval '35 days', now() - interval '34 days'),
 (9, 5, 5, 7, 'Park benches broken and unsafe',
  'Several benches in the neighbourhood park are broken with exposed metal edges. Children play around them every evening.',
  'RESOLVED', 'MEDIUM', now() - interval '38 days', now() - interval '33 days', now() - interval '32 days'),

-- Stormwater Drains (dept 6)
 (2, 6, 1, 8, 'Storm drain blocked and overflowing',
  'The storm water drain at the junction is blocked with silt and plastic. It overflows onto the road whenever it rains.',
  'RESOLVED', 'HIGH',   now() - interval '35 days', now() - interval '33 days', now() - interval '34 days 4 hours'),
 (7, 6, 4, 8, 'Open drain without cover',
  'A section of the storm water drain has no cover slab. It is an open hazard right next to where children walk to school.',
  'RESOLVED', 'CRITICAL', now() - interval '30 days', now() - interval '28 days', now() - interval '29 days 18 hours');


-- ---------------------------------------------------------------------
-- 7. NEW, LIVE COMPLAINTS
--
--    Complaints 15-18 are the duplicate cluster: four different
--    citizens in ward 1 reporting the same pothole in different words.
--    They are filed without a department so that the routing trigger
--    assigns one when the embedding is inserted below.
-- ---------------------------------------------------------------------
INSERT INTO complaint
    (citizen_id, ward_id, title, description, status, priority,
     latitude, longitude, filed_at, sla_deadline)
VALUES
 (1, 1, 'Huge pothole near the bus stop',
  'There is a very large pothole on the main road right next to the bus stop. Bikes keep swerving around it and someone will fall.',
  'OPEN', 'HIGH', 12.991500, 77.539800, now() - interval '30 hours', now() + interval '42 hours'),

 (2, 1, 'Dangerous crater on main road',
  'A deep crater has opened up on the main road close to the bus stop. It is dangerous for two wheelers especially after rain.',
  'OPEN', 'HIGH', 12.991600, 77.539900, now() - interval '26 hours', now() + interval '46 hours'),

 (3, 1, 'Pothole near bus stop not fixed',
  'The pothole on the main road by the bus stop is getting bigger. Two wheelers swerve into oncoming traffic to avoid it.',
  'OPEN', 'HIGH', 12.991450, 77.539750, now() - interval '20 hours', now() + interval '52 hours'),

 (2, 1, 'Road damage close to bus shelter',
  'Large pothole next to the bus shelter on the main road. Dangerous for bikes and it has been there for over a week now.',
  'OPEN', 'MEDIUM', 12.991550, 77.539850, now() - interval '14 hours', now() + interval '58 hours'),

-- a genuinely different complaint in the same ward
 (3, 1, 'Garbage pile at street corner',
  'Household garbage has been piling up at the street corner for several days. The collection vehicle is skipping our street.',
  'OPEN', 'MEDIUM', 12.992000, 77.540500, now() - interval '12 hours', now() + interval '36 hours'),

-- complaints in other wards
 (4, 2, 'Water pipeline burst on 5th cross',
  'A municipal water pipeline has burst on 5th cross and water is flooding down the road. Supply to our lane has stopped completely.',
  'OPEN', 'CRITICAL', 12.995000, 77.552000, now() - interval '8 hours', now() + interval '16 hours'),

 (6, 3, 'Street light out on the whole stretch',
  'None of the street lights on our stretch have been working for the last four nights. It is pitch dark after 7 pm.',
  'OPEN', 'MEDIUM', 13.003000, 77.570000, now() - interval '6 hours', now() + interval '42 hours'),

 (8, 4, 'Drain overflowing after yesterday rain',
  'The storm water drain near the junction overflowed after yesterday rain and the water has not drained away at all.',
  'OPEN', 'HIGH', 12.971000, 77.640000, now() - interval '5 hours', now() + interval '31 hours'),

-- two complaints already past their deadline, to demonstrate escalation
 (9, 5, 'Broken footpath slabs outside school',
  'Several footpath slabs outside the school gate are broken and lifted. Children trip over them during the morning rush.',
  'OPEN', 'HIGH', 12.925000, 77.583000, now() - interval '5 days', now() - interval '2 days'),

 (10, 6, 'Fallen tree branch blocking the lane',
  'A large tree branch fell during the storm and is still lying across the lane. Cars cannot pass through at all.',
  'OPEN', 'HIGH', 12.935000, 77.624000, now() - interval '6 days', now() - interval '1 day');


-- ---------------------------------------------------------------------
-- 8. ATTACHMENTS (the second multivalued attribute)
-- ---------------------------------------------------------------------
INSERT INTO complaint_attachment (complaint_id, attachment_url) VALUES
    (15, 'https://storage.example.com/aegis/c15_photo1.jpg'),
    (15, 'https://storage.example.com/aegis/c15_photo2.jpg'),
    (16, 'https://storage.example.com/aegis/c16_photo1.jpg'),
    (20, 'https://storage.example.com/aegis/c20_photo1.jpg');


-- ---------------------------------------------------------------------
-- 9. EMBEDDINGS
--
--    Inserting into complaint_embedding fires t_embedding_auto_route,
--    so the live complaints above get routed to a department
--    automatically as each embedding lands.
--
--    Historical complaints are embedded first so that the routing
--    majority vote has data to work with.
-- ---------------------------------------------------------------------
INSERT INTO complaint_embedding (complaint_id, embedding, model_name)
SELECT complaint_id,
       fn_demo_embedding(title || ' ' || description),
       'demo-hashing-384'
FROM complaint
WHERE status = 'RESOLVED'
ORDER BY complaint_id;

INSERT INTO complaint_embedding (complaint_id, embedding, model_name)
SELECT complaint_id,
       fn_demo_embedding(title || ' ' || description),
       'demo-hashing-384'
FROM complaint
WHERE status <> 'RESOLVED'
ORDER BY complaint_id;


-- ---------------------------------------------------------------------
-- 10. FEEDBACK on some resolved complaints
-- ---------------------------------------------------------------------
INSERT INTO feedback (complaint_id, rating, comments) VALUES
    (1,  5, 'Fixed within three days. Very satisfied.'),
    (2,  4, 'Took a while but the road is usable now.'),
    (4,  5, 'Water supply restored quickly, thank you.'),
    (5,  3, 'Leak was fixed but the road was left dug up.'),
    (7,  4, 'Collection resumed after the complaint.'),
    (9,  5, 'Light repaired the next day.'),
    (13, 4, 'Drain cleared before the next rain.'),
    (14, 5, 'Cover slab installed promptly. Much safer now.');


-- ---------------------------------------------------------------------
-- 11. MERGE THE DUPLICATE CLUSTER
--
--     Complaints 16, 17 and 18 are the same pothole as complaint 15.
--     fn_merge_duplicate performs all three steps of each merge inside
--     one transaction: write the link, mark the child MERGED, and
--     increment the parent's counter.
--
--     The similarity scores passed here are the ones fn_find_duplicates
--     actually returned for this seed data.
-- ---------------------------------------------------------------------
SELECT fn_merge_duplicate(16, 15, 0.72, 2);
SELECT fn_merge_duplicate(17, 15, 0.64, 2);
SELECT fn_merge_duplicate(18, 15, 0.59, 2);


-- ---------------------------------------------------------------------
-- 12. Refresh the dashboard view now that data exists
-- ---------------------------------------------------------------------
REFRESH MATERIALIZED VIEW mv_department_performance;
