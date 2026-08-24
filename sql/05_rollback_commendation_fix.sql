-- Standalone rollback for 03_apply_commendation_fix.sql.
-- Run only while mangosd is stopped. The backup tables must exist.
USE classicmangos;

DELETE FROM creature_questrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
INSERT INTO creature_questrelation
SELECT * FROM aq_backup_20260812_creature_questrelation;

DELETE FROM creature_involvedrelation
WHERE quest IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
INSERT INTO creature_involvedrelation
SELECT * FROM aq_backup_20260812_creature_involvedrelation;

DELETE FROM locales_quest
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
INSERT INTO locales_quest
SELECT * FROM aq_backup_20260812_locales_quest;

DELETE FROM quest_template
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
INSERT INTO quest_template
SELECT * FROM aq_backup_20260812_quest_template;

SELECT 'rollback_complete' AS result;
