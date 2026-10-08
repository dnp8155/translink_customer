-- Return Translink Database Schema v1.0 (Developer-Ready)
-- WARNING: This will drop existing tables. Do not run on a production database with real data unless you intend to reset.

-- 1. PROFILES
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    mobile TEXT NOT NULL,
    email TEXT,
    role TEXT CHECK (role IN ('customer', 'partner', 'admin')),
    profile_photo_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. PARTNERS
CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    business_name TEXT,
    owner_name TEXT NOT NULL,
    mobile TEXT NOT NULL,
    alternate_mobile TEXT,
    email TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    pincode TEXT,
    gst_number TEXT,
    pan_number TEXT,
    onboarding_status TEXT, -- pending, in_progress, completed, rejected, suspended
    verification_status TEXT, -- pending, verified, rejected
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. TRUCKS
CREATE TABLE IF NOT EXISTS trucks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID REFERENCES partners(id) ON DELETE CASCADE,
    truck_number TEXT UNIQUE NOT NULL,
    truck_type TEXT NOT NULL,
    body_type TEXT,
    capacity_kg NUMERIC NOT NULL,
    length_ft NUMERIC,
    width_ft NUMERIC,
    height_ft NUMERIC,
    registration_year INTEGER,
    status TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. TRUCK DOCUMENTS
CREATE TABLE IF NOT EXISTS truck_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    truck_id UUID REFERENCES trucks(id) ON DELETE CASCADE,
    document_type TEXT, -- rc, insurance, permit, fitness, etc.
    document_number TEXT,
    document_url TEXT NOT NULL,
    issue_date DATE,
    expiry_date DATE,
    verification_status TEXT, -- pending, verified, rejected
    verified_by UUID REFERENCES auth.users(id),
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. DRIVERS
CREATE TABLE IF NOT EXISTS drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID REFERENCES partners(id) ON DELETE CASCADE,
    current_truck_id UUID REFERENCES trucks(id) ON DELETE SET NULL,
    full_name TEXT NOT NULL,
    mobile TEXT NOT NULL,
    alternate_mobile TEXT,
    license_number TEXT,
    license_expiry_date DATE,
    license_document_url TEXT,
    status TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. RETURN TRIPS
CREATE TABLE IF NOT EXISTS return_trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    truck_id UUID REFERENCES trucks(id) ON DELETE CASCADE,
    partner_id UUID REFERENCES partners(id) ON DELETE CASCADE,
    origin_location TEXT NOT NULL,
    origin_city TEXT NOT NULL,
    origin_state TEXT NOT NULL,
    origin_latitude NUMERIC,
    origin_longitude NUMERIC,
    destination_location TEXT NOT NULL,
    destination_city TEXT NOT NULL,
    destination_state TEXT NOT NULL,
    destination_latitude NUMERIC,
    destination_longitude NUMERIC,
    available_date DATE NOT NULL,
    available_from_time TIME,
    available_until_time TIME,
    total_capacity_kg NUMERIC NOT NULL,
    available_capacity_kg NUMERIC NOT NULL,
    truck_type TEXT NOT NULL,
    body_type TEXT,
    status TEXT, -- available, partially_available, full, unavailable, cancelled
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 7. TRIP STOPS
CREATE TABLE IF NOT EXISTS trip_stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    return_trip_id UUID REFERENCES return_trips(id) ON DELETE CASCADE,
    stop_order INTEGER NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    latitude NUMERIC,
    longitude NUMERIC,
    estimated_arrival TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(return_trip_id, stop_order)
);

-- 8. TRUCK LOCATIONS
CREATE TABLE IF NOT EXISTS truck_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    truck_id UUID UNIQUE REFERENCES trucks(id) ON DELETE CASCADE,
    latitude NUMERIC NOT NULL,
    longitude NUMERIC NOT NULL,
    location_name TEXT,
    city TEXT,
    state TEXT,
    accuracy_meters NUMERIC,
    source TEXT, -- gps, manual, admin
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 9. LOCATION HISTORY
CREATE TABLE IF NOT EXISTS location_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    truck_id UUID REFERENCES trucks(id) ON DELETE CASCADE,
    latitude NUMERIC NOT NULL,
    longitude NUMERIC NOT NULL,
    location_name TEXT,
    city TEXT,
    state TEXT,
    accuracy_meters NUMERIC,
    source TEXT,
    recorded_at TIMESTAMPTZ DEFAULT now()
);

-- 10. CUSTOMERS
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    mobile TEXT NOT NULL,
    email TEXT,
    company_name TEXT,
    gst_number TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 11. CUSTOMER LOCATIONS
CREATE TABLE IF NOT EXISTS customer_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    location_name TEXT NOT NULL,
    address TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT,
    pincode TEXT,
    latitude NUMERIC,
    longitude NUMERIC,
    location_type TEXT, -- pickup, drop, other
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 12. SEARCH REQUESTS
CREATE TABLE IF NOT EXISTS search_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    pickup_location TEXT NOT NULL,
    pickup_city TEXT NOT NULL,
    pickup_state TEXT,
    pickup_latitude NUMERIC,
    pickup_longitude NUMERIC,
    drop_location TEXT NOT NULL,
    drop_city TEXT NOT NULL,
    drop_state TEXT,
    drop_latitude NUMERIC,
    drop_longitude NUMERIC,
    required_date DATE,
    required_capacity_kg NUMERIC,
    truck_type TEXT,
    body_type TEXT,
    material_type TEXT,
    search_status TEXT,
    results_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 13. SALES LEADS
CREATE TABLE IF NOT EXISTS sales_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    search_request_id UUID REFERENCES search_requests(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES profiles(id),
    lead_source TEXT,
    lead_status TEXT,
    priority TEXT,
    contact_attempts INTEGER DEFAULT 0,
    last_contacted_at TIMESTAMPTZ,
    next_followup_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 14. CONTACT LOGS
CREATE TABLE IF NOT EXISTS contact_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    partner_id UUID REFERENCES partners(id) ON DELETE SET NULL,
    truck_id UUID REFERENCES trucks(id) ON DELETE SET NULL,
    sales_lead_id UUID REFERENCES sales_leads(id) ON DELETE SET NULL,
    performed_by UUID REFERENCES profiles(id),
    contact_type TEXT, -- call, whatsapp, sms
    contact_direction TEXT,
    outcome TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 15. FAVORITES
CREATE TABLE IF NOT EXISTS favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    truck_id UUID REFERENCES trucks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(customer_id, truck_id)
);

-- 16. REPORTS
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_profile_id UUID REFERENCES profiles(id),
    reported_partner_id UUID REFERENCES partners(id),
    reported_truck_id UUID REFERENCES trucks(id),
    report_type TEXT,
    description TEXT,
    status TEXT,
    resolution_notes TEXT,
    resolved_by UUID REFERENCES auth.users(id),
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 17. NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    notification_type TEXT,
    reference_id UUID,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ
);

-- 18. ADMIN USERS
CREATE TABLE IF NOT EXISTS admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    department TEXT,
    designation TEXT,
    permissions JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 19. AUDIT LOGS
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 20. SUPPORT TICKETS
CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID REFERENCES profiles(id),
    assigned_to UUID REFERENCES profiles(id),
    category TEXT,
    subject TEXT,
    description TEXT,
    priority TEXT,
    status TEXT,
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- INDEXES (As per PDF recommendations)
CREATE INDEX IF NOT EXISTS idx_return_trips_search ON return_trips (available_date, origin_city, destination_city, status);
CREATE INDEX IF NOT EXISTS idx_return_trips_capacity ON return_trips (available_date, available_capacity_kg);
