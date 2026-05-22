# zones.json Configuration Guide

## Overview

The `config/zones.json` file is a critical configuration file that defines the geographic coverage and service categories for the Trato platform. This file is used by the dual WhatsApp flows feature to:

1. Detect a client's region from their phone number prefix
2. Present available zones for service requests
3. Display service categories for provider discovery
4. Route clients to appropriate providers based on location

**⚠️ IMPORTANT**: This file is loaded into memory on application boot. Any changes require an application restart to take effect.

---

## File Structure

The JSON file contains two top-level arrays:

```json
{
  "states": [...],
  "categories": [...]
}
```

### 1. States Array

Each state object represents a Mexican state where Trato operates.

#### State Object Schema

```json
{
  "name": "string",              // State name (e.g., "Veracruz")
  "phone_prefixes": ["string"],  // Array of phone area codes
  "cities": [...]                // Array of city objects
}
```

#### Example State

```json
{
  "name": "Veracruz",
  "phone_prefixes": ["229", "228", "271", "278", "282", "283", "284", "288"],
  "cities": [
    {
      "name": "Veracruz",
      "type": "capital",
      "zones": ["Centro Histórico", "Boca del Río", "Mocambo"]
    }
  ]
}
```

### 2. Cities Array

Each city object within a state represents a city or municipality where services are available.

#### City Object Schema

```json
{
  "name": "string",    // City name (e.g., "Veracruz")
  "type": "string",    // City classification (see below)
  "zones": ["string"]  // Array of zone/neighborhood names
}
```

#### City Types

- **`capital`**: State capital city (e.g., Veracruz city in Veracruz state)
- **`capital_state`**: State capital (e.g., Xalapa in Veracruz state)
- **`major_city`**: Major city with significant population (e.g., Coatzacoalcos)

**Note**: The `type` field is currently informational and not used in business logic, but may be used for future features like prioritization or display ordering.

### 3. Zones Array

Each zone represents a neighborhood, district, or area within a city where providers can offer services.

- Zones are simple strings
- Zone names should be recognizable to local residents
- Zones are used for provider filtering and client discovery

#### Example Zones

```json
"zones": [
  "Centro Histórico",
  "Boca del Río",
  "Mocambo",
  "Costa Verde"
]
```

### 4. Categories Array

The categories array defines all service types available on the platform.

#### Category Object Schema

```json
{
  "id": "string",    // Unique identifier (lowercase, no spaces)
  "name": "string",  // Display name (e.g., "Plomería")
  "icon": "string",  // Emoji icon for visual representation
  "slug": "string"   // URL-friendly identifier
}
```

#### Example Category

```json
{
  "id": "plomeria",
  "name": "Plomería",
  "icon": "🔧",
  "slug": "plomeria"
}
```

---

## How the Data is Used

### Phone Prefix Detection (C2A Flow)

When a client messages the client WhatsApp number:

1. System extracts phone prefix from client's number (e.g., "229" from "+52 229 123 4567")
2. Searches all states for matching prefix in `phone_prefixes` array
3. If match found, greets client with detected region: "Veo que eres de Veracruz"
4. Presents zones from that state for selection

**Code Reference**: `app/services/zones_service.rb#detect_state_from_prefix`

### Zone Selection

After region confirmation:

- **If client confirms region**: Shows zones only from detected state
- **If client selects "otro lugar"**: Shows all zones from all states

**Code Reference**: `app/services/zones_service.rb#zones_for_state` and `#all_zones`

### Category Selection

After zone selection:

1. System presents first 5 categories from `categories` array
2. Includes "Ver más categorías" option
3. If selected, shows remaining categories on page 2

**Code Reference**: `app/services/zones_service.rb#categories_page`

### Provider Filtering

After category selection:

- System queries database for active providers matching:
  - Selected zone (stored in `providers.city` or similar field)
  - Selected category (via `provider_categories` join table)

**Code Reference**: `app/services/assistants/provider_search_service.rb`

---

## How to Update zones.json

### Adding a New State

1. Open `config/zones.json`
2. Add new state object to `states` array:

```json
{
  "name": "Nuevo León",
  "phone_prefixes": ["81", "818", "826", "828"],
  "cities": [
    {
      "name": "Monterrey",
      "type": "capital",
      "zones": ["Centro", "San Pedro Garza García", "Santa Catarina"]
    }
  ]
}
```

3. Validate JSON syntax (use online validator or `jq` command)
4. Restart application to load new data

### Adding a New City to Existing State

1. Locate the state object in `states` array
2. Add new city object to that state's `cities` array:

```json
{
  "name": "Orizaba",
  "type": "major_city",
  "zones": ["Centro", "Río Blanco", "Nogales"]
}
```

3. Validate JSON syntax
4. Restart application

### Adding Zones to Existing City

1. Locate the city object within its state
2. Add zone names to the `zones` array:

```json
"zones": [
  "Centro Histórico",
  "Boca del Río",
  "Mocambo",
  "Costa Verde",
  "Nuevo Veracruz"  // ← New zone
]
```

3. Validate JSON syntax
4. Restart application

### Adding a New Phone Prefix

1. Locate the state object
2. Add prefix to `phone_prefixes` array:

```json
"phone_prefixes": ["229", "228", "271", "278", "282", "283", "284", "288", "285"]
```

3. Validate JSON syntax
4. Restart application

**⚠️ Important**: Phone prefixes should be 2-3 digit strings without country code (e.g., "229" not "+52229")

### Adding a New Service Category

1. Add new category object to `categories` array:

```json
{
  "id": "pintura",
  "name": "Pintura",
  "icon": "🎨",
  "slug": "pintura"
}
```

2. Ensure:
   - `id` is unique and lowercase
   - `slug` is URL-friendly (lowercase, hyphens for spaces)
   - `icon` is a single emoji character
   - `name` is the display name in Spanish

3. Validate JSON syntax
4. Restart application

**Note**: After adding a category, you may need to update provider records in the database to associate providers with the new category.

---

## Validation Rules

### Required Fields

All fields shown in the schemas above are **required**. Missing fields will cause application boot failure.

### Data Types

- `name`: Non-empty string
- `phone_prefixes`: Array of strings (2-3 digits each)
- `type`: One of: "capital", "capital_state", "major_city"
- `zones`: Array of non-empty strings
- `id`: Lowercase string, no spaces
- `slug`: URL-friendly string (lowercase, hyphens)
- `icon`: Single emoji character

### Uniqueness Constraints

- State names must be unique
- Category IDs must be unique
- Category slugs must be unique
- Phone prefixes should not overlap between states (though system will use first match)

---

## Testing Changes

After modifying `zones.json`:

### 1. Validate JSON Syntax

```bash
# Using jq (if installed)
jq . config/zones.json

# Or use online validator: https://jsonlint.com/
```

### 2. Test in Rails Console

```ruby
# Start Rails console
rails console

# Test ZonesService methods
ZonesService.all_states
# => Should return array of state hashes

ZonesService.detect_state_from_prefix("229")
# => Should return "Veracruz"

ZonesService.zones_for_state("Veracruz")
# => Should return array of zones for Veracruz

ZonesService.all_categories
# => Should return array of category hashes

ZonesService.categories_page(1)
# => Should return first 5 categories + "Ver más" option
```

### 3. Test in Development Environment

1. Restart Rails server: `bin/dev`
2. Send test message to client WhatsApp number
3. Verify region detection works with new phone prefixes
4. Verify new zones appear in zone selection list
5. Verify new categories appear in category selection list

### 4. Run Automated Tests

```bash
# Run ZonesService tests
bundle exec rspec spec/services/zones_service_spec.rb

# Run integration tests
bundle exec rspec spec/integration/client_region_discovery_spec.rb
```

---

## Common Issues and Troubleshooting

### Issue: Application fails to boot after changes

**Cause**: Invalid JSON syntax

**Solution**:
1. Validate JSON using `jq . config/zones.json`
2. Check for:
   - Missing commas between array elements
   - Missing closing brackets/braces
   - Trailing commas (not allowed in JSON)
   - Unescaped quotes in strings

### Issue: Phone prefix not detected

**Cause**: Prefix not in `phone_prefixes` array or wrong format

**Solution**:
1. Verify prefix is 2-3 digits (e.g., "229" not "+52229")
2. Verify prefix is in correct state's array
3. Restart application after adding prefix

### Issue: New zones not appearing

**Cause**: Application not restarted or zones added to wrong city

**Solution**:
1. Verify zones added to correct city object
2. Restart application: `bin/dev`
3. Clear Rails cache if using caching: `Rails.cache.clear`

### Issue: Category not showing in WhatsApp list

**Cause**: Category added but pagination logic not updated

**Solution**:
1. Verify category added to `categories` array
2. Check `ZonesService.categories_page(1)` returns expected categories
3. If more than 10 categories, verify page 2 logic works

---

## Performance Considerations

### Memory Loading

The entire `zones.json` file is loaded into memory on application boot via:

```ruby
# config/initializers/zones.rb
ZONES_DATA = JSON.parse(File.read(Rails.root.join('config', 'zones.json')))
```

**Implications**:
- Fast read access (no file I/O on each request)
- Changes require application restart
- File size should remain reasonable (< 1MB recommended)

### Caching

`ZonesService` methods read from the in-memory `ZONES_DATA` constant, so no additional caching is needed.

---

## Migration to Database (Future Enhancement)

Currently, zones and categories are stored in JSON for simplicity. For future scalability, consider migrating to database tables:

### Proposed Schema

```ruby
# States table
create_table :states do |t|
  t.string :name, null: false
  t.jsonb :phone_prefixes, default: []
  t.timestamps
end

# Cities table
create_table :cities do |t|
  t.references :state, null: false, foreign_key: true
  t.string :name, null: false
  t.string :city_type, null: false
  t.timestamps
end

# Zones table
create_table :zones do |t|
  t.references :city, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
end

# Categories table (may already exist)
create_table :categories do |t|
  t.string :name, null: false
  t.string :slug, null: false
  t.string :icon
  t.timestamps
end
```

**Benefits**:
- No application restart needed for changes
- Admin panel can manage zones/categories
- Better data validation and constraints
- Easier to add metadata (e.g., zone boundaries, population)

**Tradeoffs**:
- More complex queries
- Requires database migrations
- Need to build admin UI for management

---

## Related Files

- **Service**: `app/services/zones_service.rb` - Loads and queries zones data
- **Initializer**: `config/initializers/zones.rb` - Loads JSON into memory on boot
- **Tests**: `spec/services/zones_service_spec.rb` - Unit tests for ZonesService
- **Integration Tests**: `spec/integration/client_region_discovery_spec.rb` - End-to-end flow tests

---

## Contact

For questions about zones.json structure or to request changes, contact the development team or create an issue in the project repository.

---

**Last Updated**: May 21, 2026
**Version**: 1.0
**Maintained By**: Trato Development Team
