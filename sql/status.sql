-- opx77_status. One row per character: the gameplay needs this resource owns.
-- server/main.lua applies the same statement at boot; this is the operator's copy.
-- No foreign key to opx77_characters: load order across resources is not ours to decide.

CREATE TABLE IF NOT EXISTS opx77_character_status (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    needs JSON NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;
