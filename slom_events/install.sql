-- ينفذ مرة واحدة في قاعدة mysql-async الخاصة بالخادم.
CREATE TABLE IF NOT EXISTS slom_events_state (
    id TINYINT UNSIGNED NOT NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
    payload LONGTEXT NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT IGNORE INTO slom_events_state (id, revision, payload)
VALUES (1, 0, '{"version":1,"nextEvent":0,"events":{},"players":{},"ledger":{},"logs":{},"schedules":{},"purchases":{},"automatic":false,"created":0}');
