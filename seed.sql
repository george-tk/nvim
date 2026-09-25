CREATE TABLE IF NOT EXISTS users (
    id          SERIAL PRIMARY KEY,
    email       TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    birth_date  DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    category    TEXT NOT NULL,
    price       NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'shipped',
   'delivered', 'cancelled')),
    total       NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
    order_id    INTEGER NOT NULL REFERENCES orders(id),
    product_id  INTEGER NOT NULL REFERENCES products(id),
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, product_id)
);

INSERT INTO users (email, name, birth_date, created_at) VALUES
    ('alice@example.com', 'Alice Smith',   '1990-04-12', now() - interval '2 years'),
    ('bob@example.com',   'Bob Johnson',   '1985-11-30', now() - interval '18 months'),
    ('carol@example.com', 'Carol White',   '1995-07-22', now() - interval '1 year'),
    ('dave@example.com',  'Dave Brown',    '1988-02-03', now() - interval '6 months'),
    ('erin@example.com',  'Erin Davis',    '1992-09-15', now() - interval '3 months');

INSERT INTO products (name, category, price, stock) VALUES
    ('Mechanical Keyboard',  'electronics',  129.99, 25),
    ('Wireless Mouse',       'electronics',   39.99, 60),
    ('USB-C Hub',            'electronics',   59.50, 18),
    ('Desk Lamp',            'home',          24.00, 0),
    ('Ergonomic Chair',      'furniture',    349.00, 7),
    ('Standing Desk',        'furniture',    529.00, 3),
    ('Notebook',             'office',         6.99, 200),
    ('Pilot Pen (10 pack)',  'office',        12.40, 140);

INSERT INTO orders (user_id, status, total, created_at) VALUES
    (1, 'delivered', 169.98, now() - interval '30 days'),
    (1, 'pending',    24.00, now() - interval '1 day'),
    (2, 'paid',      349.00, now() - interval '10 days'),
    (3, 'shipped',    72.49, now() - interval '4 days'),
    (3, 'cancelled', 529.00, now() - interval '15 days'),
    (4, 'delivered',  19.39, now() - interval '8 days'),
    (5, 'delivered',  39.99, now() - interval '2 days');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 1, 129.99),
    (1, 2, 1,  39.99),
    (2, 4, 1,  24.00),
    (3, 5, 1, 349.00),
    (4, 3, 1,  59.50),
    (4, 7, 2,   6.99),
    (5, 6, 1, 529.00),
    (6, 8, 1,  12.40),
    (6, 7, 1,   6.99),
    (7, 2, 1,  39.99);

-- Additional bulk data for scrolling and grid navigation tests
INSERT INTO users (email, name, birth_date, created_at)
SELECT
    'user_' || i || '@example.com',
    (ARRAY['James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth', 'David', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica', 'Thomas', 'Sarah', 'Charles', 'Karen'])[1 + (i % 20)] || ' ' ||
    (ARRAY['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin'])[1 + ((i * 7) % 20)],
    '1970-01-01'::date + (i * 73 % 15000),
    now() - (i || ' days')::interval
FROM generate_series(6, 150) AS i
ON CONFLICT (email) DO NOTHING;

INSERT INTO products (name, category, price, stock)
SELECT
    (ARRAY['Pro', 'Ultra', 'Super', 'Eco', 'Smart', 'Wireless', 'Ergonomic', 'Compact', 'Heavy-Duty', 'Premium'])[1 + (i % 10)] || ' ' ||
    (ARRAY['Keyboard', 'Monitor', 'Mouse', 'Desk', 'Chair', 'Lamp', 'Headphones', 'Speaker', 'Webcam', 'Microphone', 'Backpack', 'Notebook', 'Coffee Mug', 'Cable Organizer', 'Phone Stand'])[1 + ((i * 3) % 15)] || ' v' || (i % 5 + 1),
    (ARRAY['electronics', 'furniture', 'office', 'home', 'accessories'])[1 + (i % 5)],
    round((9.99 + (i * 13.7 % 450))::numeric, 2),
    (i * 17) % 150
FROM generate_series(9, 150) AS i;

INSERT INTO orders (user_id, status, total, created_at)
SELECT
    1 + (i % 150),
    (ARRAY['pending', 'paid', 'shipped', 'delivered', 'cancelled'])[1 + (i % 5)],
    round((15.00 + (i * 23.4 % 850))::numeric, 2),
    now() - (i || ' hours')::interval
FROM generate_series(8, 200) AS i;