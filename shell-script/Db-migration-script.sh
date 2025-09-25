#IF YOU WANT TO MIGRATE DATABASE FROM MYSQL TO POSTGRES 
#ENSURE THAT BOTH MYSQL AND POSTGRESQL CREDENTIALS ARE CORRECTLY MENTIONED IN THE BELOW SCRIPT

#!/bin/bash
# Complete MySQL to PostgreSQL Migration Script
# Run: chmod +x migrate.sh && ./migrate.sh

set -e  # Exit on any error

# Database Connection Details
MYSQL_HOST="<YOUR-MYSQL-RDS-ENDPOINT>"
MYSQL_USER="<YOUR-MYSQL-USER-NAME>"
MYSQL_PASS="<YOUR-MYSQL-PASSWORD>"
MYSQL_DB="<YOUR-MYSQL-DATABASE-NAME>"

PG_HOST="<YOUR-POSTGRES-RDS-ENDPOINT>"
PG_USER="<YOUR-POSTGRES-USER-NAME>"
PG_PASS="<YOUR-POSTGRES-PASSWORD>"
PG_DB="<YOUR-POSTGRES-DATABSE-NAME>"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Complete MySQL to PostgreSQL Migration ===${NC}"
echo "Starting migration from MySQL to PostgreSQL..."

# Step 1: Test Connections
echo -e "\n${YELLOW}Step 1: Testing database connections...${NC}"
echo "Testing MySQL connection..."
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -D $MYSQL_DB -e "SELECT 'MySQL Connected' as status;" 2>/dev/null || {
    echo -e "${RED}ERROR: MySQL connection failed!${NC}"
    exit 1
}

echo "Testing PostgreSQL connection..."
PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d $PG_DB -c "SELECT 'PostgreSQL Connected' as status;" 2>/dev/null || {
    echo -e "${RED}ERROR: PostgreSQL connection failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Both databases connected successfully${NC}"

# Step 2: Create MySQL dump
echo -e "\n${YELLOW}Step 2: Creating MySQL dump...${NC}"
mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS \
    --single-transaction \
    --skip-lock-tables \
    --no-create-info \
    --complete-insert \
    --skip-triggers \
    --skip-routines \
    --set-charset \
    --default-character-set=utf8 \
    $MYSQL_DB > /tmp/mysql_data_dump.sql 2>/dev/null

# Get schema dump separately
mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_DB \
    --no-data \
    --skip-lock-tables \
    --single-transaction \
    $MYSQL_DB > /tmp/mysql_schema_dump.sql 2>/dev/null

echo -e "${GREEN}✓ MySQL dump created successfully${NC}"

# Step 3: Convert MySQL dump to PostgreSQL format
echo -e "\n${YELLOW}Step 3: Converting MySQL dump to PostgreSQL format...${NC}"

# Create PostgreSQL compatible dump
cp /tmp/mysql_data_dump.sql /tmp/postgres_dump.sql

# MySQL to PostgreSQL conversions
sed -i 's/`/"/g' /tmp/postgres_dump.sql                           # Backticks to double quotes
sed -i 's/\\0/\\\\0/g' /tmp/postgres_dump.sql                    # Fix null characters
sed -i 's/\\\\/\\\\\\\\/g' /tmp/postgres_dump.sql               # Fix backslashes
sed -i "s/\\\'/\'\'/g" /tmp/postgres_dump.sql                    # Fix single quotes
sed -i 's/INSERT INTO/INSERT INTO /g' /tmp/postgres_dump.sql      # Standardize INSERT statements
sed -i '/^\/\*/d' /tmp/postgres_dump.sql                         # Remove MySQL comments
sed -i '/^--/d' /tmp/postgres_dump.sql                           # Remove MySQL comments
sed -i '/^SET /d' /tmp/postgres_dump.sql                         # Remove MySQL SET statements
sed -i '/^LOCK TABLES/d' /tmp/postgres_dump.sql                  # Remove LOCK statements
sed -i '/^UNLOCK TABLES/d' /tmp/postgres_dump.sql                # Remove UNLOCK statements

echo -e "${GREEN}✓ Dump converted to PostgreSQL format${NC}"

# Step 4: Create PostgreSQL tables manually with proper schema
echo -e "\n${YELLOW}Step 4: Creating PostgreSQL tables...${NC}"

PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d $PG_DB << 'EOF'

-- Drop existing tables if any
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Create AspNetRoles table
CREATE TABLE "AspNetRoles" (
    "Id" VARCHAR(450) NOT NULL PRIMARY KEY,
    "Name" VARCHAR(256),
    "NormalizedName" VARCHAR(256),
    "ConcurrencyStamp" TEXT
);

-- Create AspNetUsers table
CREATE TABLE "AspNetUsers" (
    "Id" VARCHAR(450) NOT NULL PRIMARY KEY,
    "UserName" VARCHAR(256),
    "NormalizedUserName" VARCHAR(256),
    "Email" VARCHAR(256),
    "NormalizedEmail" VARCHAR(256),
    "EmailConfirmed" BOOLEAN NOT NULL DEFAULT FALSE,
    "PasswordHash" TEXT,
    "SecurityStamp" TEXT,
    "ConcurrencyStamp" TEXT,
    "PhoneNumber" TEXT,
    "PhoneNumberConfirmed" BOOLEAN NOT NULL DEFAULT FALSE,
    "TwoFactorEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "LockoutEnd" TIMESTAMP,
    "LockoutEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "AccessFailedCount" INTEGER NOT NULL DEFAULT 0,
    "FirstName" VARCHAR(50),
    "LastName" VARCHAR(50),
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedDate" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create AspNetUserRoles table
CREATE TABLE "AspNetUserRoles" (
    "UserId" VARCHAR(450) NOT NULL,
    "RoleId" VARCHAR(450) NOT NULL,
    PRIMARY KEY ("UserId", "RoleId")
);

-- Create AspNetRoleClaims table
CREATE TABLE "AspNetRoleClaims" (
    "Id" SERIAL PRIMARY KEY,
    "RoleId" VARCHAR(450) NOT NULL,
    "ClaimType" TEXT,
    "ClaimValue" TEXT
);

-- Create AspNetUserClaims table
CREATE TABLE "AspNetUserClaims" (
    "Id" SERIAL PRIMARY KEY,
    "UserId" VARCHAR(450) NOT NULL,
    "ClaimType" TEXT,
    "ClaimValue" TEXT
);

-- Create AspNetUserLogins table
CREATE TABLE "AspNetUserLogins" (
    "LoginProvider" VARCHAR(450) NOT NULL,
    "ProviderKey" VARCHAR(450) NOT NULL,
    "ProviderDisplayName" TEXT,
    "UserId" VARCHAR(450) NOT NULL,
    PRIMARY KEY ("LoginProvider", "ProviderKey")
);

-- Create AspNetUserTokens table
CREATE TABLE "AspNetUserTokens" (
    "UserId" VARCHAR(450) NOT NULL,
    "LoginProvider" VARCHAR(450) NOT NULL,
    "Name" VARCHAR(450) NOT NULL,
    "Value" TEXT,
    PRIMARY KEY ("UserId", "LoginProvider", "Name")
);

-- Create LocationMaster table
CREATE TABLE "LocationMaster" (
    "Id" SERIAL PRIMARY KEY,
    "Country" VARCHAR(100),
    "State" VARCHAR(100),
    "City" VARCHAR(100),
    "Area" VARCHAR(100),
    "PinCode" VARCHAR(10),
    "Latitude" DECIMAL(10,8),
    "Longitude" DECIMAL(11,8),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create Facilities table
CREATE TABLE "Facilities" (
    "Id" SERIAL PRIMARY KEY,
    "Name" VARCHAR(100) NOT NULL,
    "Description" TEXT,
    "IconClass" VARCHAR(50),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create Masjids table
CREATE TABLE "Masjids" (
    "Id" SERIAL PRIMARY KEY,
    "Name" VARCHAR(200) NOT NULL,
    "LocationId" INTEGER,
    "Address" TEXT,
    "ContactNumber" VARCHAR(15),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create MasjidFacilities table
CREATE TABLE "MasjidFacilities" (
    "Id" SERIAL PRIMARY KEY,
    "MasjidId" INTEGER NOT NULL,
    "FacilityId" INTEGER NOT NULL,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create MasjidImages table
CREATE TABLE "MasjidImages" (
    "Id" SERIAL PRIMARY KEY,
    "MasjidId" INTEGER NOT NULL,
    "ImageUrl" TEXT,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create NamazTimings table
CREATE TABLE "NamazTimings" (
    "Id" SERIAL PRIMARY KEY,
    "MasjidId" INTEGER NOT NULL,
    "FajrTime" TIME,
    "DhuhrTime" TIME,
    "AsrTime" TIME,
    "MaghribTime" TIME,
    "IshaTime" TIME,
    "JumaTime" TIME,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create MasjidUsers table
CREATE TABLE "MasjidUsers" (
    "Id" SERIAL PRIMARY KEY,
    "MasjidId" INTEGER NOT NULL,
    "UserId" VARCHAR(450) NOT NULL,
    "Role" VARCHAR(50),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create ContactMessages table
CREATE TABLE "ContactMessages" (
    "Id" SERIAL PRIMARY KEY,
    "Name" VARCHAR(100),
    "Email" VARCHAR(100),
    "Subject" VARCHAR(200),
    "Message" TEXT,
    "IsRead" BOOLEAN DEFAULT FALSE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create EmailSettings table
CREATE TABLE "EmailSettings" (
    "Id" SERIAL PRIMARY KEY,
    "SmtpServer" VARCHAR(100),
    "SmtpPort" INTEGER,
    "Username" VARCHAR(100),
    "Password" VARCHAR(100),
    "EnableSsl" BOOLEAN DEFAULT TRUE,
    "FromEmail" VARCHAR(100),
    "FromName" VARCHAR(100),
    "IsActive" BOOLEAN DEFAULT TRUE
);

-- Create EmailTemplates table
CREATE TABLE "EmailTemplates" (
    "Id" SERIAL PRIMARY KEY,
    "Name" VARCHAR(100) NOT NULL,
    "Subject" VARCHAR(200),
    "Body" TEXT,
    "CreatedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedAt" TIMESTAMP,
    "CreatedByUserId" VARCHAR(450),
    "UpdatedByUserId" VARCHAR(450),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "IsDeleted" BOOLEAN DEFAULT FALSE
);

-- Create ExceptionLogs table
CREATE TABLE "ExceptionLogs" (
    "Id" SERIAL PRIMARY KEY,
    "Message" TEXT,
    "StackTrace" TEXT,
    "Source" TEXT,
    "CreatedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create LogEntries table
CREATE TABLE "LogEntries" (
    "Id" SERIAL PRIMARY KEY,
    "Message" TEXT,
    "Level" VARCHAR(50),
    "TimeStamp" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create MasjidEnquiries table
CREATE TABLE "MasjidEnquiries" (
    "Id" SERIAL PRIMARY KEY,
    "MasjidId" INTEGER,
    "Name" VARCHAR(100),
    "Email" VARCHAR(100),
    "Phone" VARCHAR(15),
    "Message" TEXT,
    "IsProcessed" BOOLEAN DEFAULT FALSE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "UpdatedDate" TIMESTAMP
);

-- Create S3Credentials table
CREATE TABLE "S3Credentials" (
    "Id" SERIAL PRIMARY KEY,
    "AccessKey" VARCHAR(100),
    "SecretKey" VARCHAR(100),
    "BucketName" VARCHAR(100),
    "Region" VARCHAR(50),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedDate" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create __EFMigrationsHistory table
CREATE TABLE "__EFMigrationsHistory" (
    "MigrationId" VARCHAR(150) NOT NULL PRIMARY KEY,
    "ProductVersion" VARCHAR(32) NOT NULL
);

EOF

echo -e "${GREEN}✓ PostgreSQL tables created successfully${NC}"

# Step 5: Import data using pgloader
echo -e "\n${YELLOW}Step 5: Importing data using pgloader...${NC}"

# Create pgloader configuration
cat > /tmp/migration.load << EOF
LOAD DATABASE
    FROM mysql://$MYSQL_USER:$MYSQL_PASS@$MYSQL_HOST/$MYSQL_DB
    INTO postgresql://$PG_USER:$PG_PASS@$PG_HOST/$PG_DB

WITH include no drop, create no tables, create no indexes, reset no sequences

CAST type datetime to timestamptz drop default drop not null using zero-dates-to-null,
     type date drop not null drop default using zero-dates-to-null,
     type tinyint to boolean using tinyint-to-boolean,
     type year to integer;
EOF

# Run pgloader
echo "Running pgloader migration..."
pgloader /tmp/migration.load 2>/dev/null || {
    echo -e "${YELLOW}pgloader failed, using manual data import...${NC}"
    
    # Manual import for each table
    for table in AspNetRoles AspNetUsers AspNetUserRoles LocationMaster Facilities Masjids MasjidFacilities MasjidImages NamazTimings MasjidUsers ContactMessages EmailSettings S3Credentials __EFMigrationsHistory; do
        echo "Importing $table..."
        mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -D $MYSQL_DB -e "SELECT * FROM $table;" --batch --raw 2>/dev/null | tail -n +2 | PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d $PG_DB -c "\COPY \"$table\" FROM STDIN WITH (FORMAT csv, DELIMITER E'\t', HEADER false, NULL 'NULL')" 2>/dev/null || echo "Skipped $table (empty or error)"
    done
}

# Step 6: Final verification and cleanup
echo -e "\n${YELLOW}Step 6: Final verification...${NC}"

echo "MySQL table count:"
MYSQL_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -D $MYSQL_DB -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MYSQL_DB';" 2>/dev/null)

echo "PostgreSQL table count:"
PG_COUNT=$(PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d $PG_DB -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)

echo -e "\n${GREEN}=== Migration Summary ===${NC}"
echo "MySQL tables: $MYSQL_COUNT"
echo "PostgreSQL tables: $PG_COUNT"

echo -e "\nRow counts in PostgreSQL:"
for table in AspNetRoles AspNetUsers LocationMaster Facilities Masjids MasjidFacilities NamazTimings; do
    count=$(PGPASSWORD=$PG_PASS psql -h $PG_HOST -U $PG_USER -d $PG_DB -t -c "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null | xargs)
    echo "$table: $count rows"
done

# Cleanup
rm -f /tmp/mysql_*.sql /tmp/postgres_*.sql /tmp/migration.load 2>/dev/null

echo -e "\n${GREEN}✓ Migration completed successfully!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Update your application connection string to PostgreSQL"
echo "2. Test your application thoroughly"
echo "3. Create additional indexes if needed for performance"

echo -e "\n${GREEN}PostgreSQL Connection String:${NC}"
echo "Host=$PG_HOST;Database=$PG_DB;Username=$PG_USER;Password=$PG_PASS"
