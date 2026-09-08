-- Migration 000010: Master Retailers Table for 1,285+ Series Master Records

CREATE TABLE IF NOT EXISTS master_retailers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    distributor_entity VARCHAR(100) NOT NULL,
    series_prefix VARCHAR(30) NOT NULL,
    customer_code VARCHAR(100) NOT NULL DEFAULT '',
    company_code VARCHAR(100) NOT NULL DEFAULT '',
    retailer_name VARCHAR(255) NOT NULL,
    gstin VARCHAR(15) NOT NULL DEFAULT '',
    pan VARCHAR(10) NOT NULL DEFAULT '',
    address_line1 TEXT NOT NULL DEFAULT '',
    address_line2 TEXT NOT NULL DEFAULT '',
    address_line3 TEXT NOT NULL DEFAULT '',
    city VARCHAR(100) NOT NULL DEFAULT '',
    state VARCHAR(100) NOT NULL DEFAULT '',
    pincode VARCHAR(10) NOT NULL DEFAULT '',
    contact_person VARCHAR(100) NOT NULL DEFAULT '',
    phone_number VARCHAR(20) NOT NULL DEFAULT '',
    email VARCHAR(100) NOT NULL DEFAULT '',
    salesman_code VARCHAR(50) NOT NULL DEFAULT '',
    salesman_name VARCHAR(100) NOT NULL DEFAULT '',
    route_code VARCHAR(50) NOT NULL DEFAULT '',
    route_name VARCHAR(100) NOT NULL DEFAULT '',
    channel_group VARCHAR(50) NOT NULL DEFAULT '',
    credit_limit NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    credit_days INT NOT NULL DEFAULT 0,
    is_key_account BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_master_retailers_series ON master_retailers(series_prefix);
CREATE INDEX IF NOT EXISTS idx_master_retailers_gstin ON master_retailers(gstin);
CREATE INDEX IF NOT EXISTS idx_master_retailers_code ON master_retailers(customer_code);
CREATE INDEX IF NOT EXISTS idx_master_retailers_name ON master_retailers(retailer_name);
