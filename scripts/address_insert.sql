DROP TABLE IF EXISTS addresses;
CREATE TABLE addresses (id INTEGER PRIMARY KEY AUTOINCREMENT, full_name TEXT NOT NULL, cho_seong TEXT NOT NULL);
BEGIN TRANSACTION;
CREATE INDEX idx_cho_seong ON addresses (cho_seong);
CREATE INDEX idx_full_name ON addresses (full_name);
COMMIT;
