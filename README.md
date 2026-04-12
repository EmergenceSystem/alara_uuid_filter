# alara_uuid_filter
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.md)

An [em_filter](https://hex.pm/packages/em_filter) agent that exposes the [alara_uuid](https://hex.pm/packages/alara_uuid) UUID generation API as an [Emergence](https://github.com/EmergenceSystem/em_disco) agent.

Generates RFC 9562 compliant UUID v7 (time-ordered, ALARA-entropy) and UUID v5 (name-based, deterministic).

## Actions

| Action | Parameters | Default | Returns |
|---|---|---|---|
| `v7` | `n` (optional) | 1 | one or N UUID v7 strings |
| `v5` | `namespace`, `name` | `dns`, `""` | UUID v5 string |
| `to_string` | `uuid` (hex/standard), `format` | `standard` | formatted UUID string |
| `ns_dns` | — | — | RFC 9562 DNS namespace UUID |
| `ns_url` | — | — | RFC 9562 URL namespace UUID |
| `ns_oid` | — | — | RFC 9562 OID namespace UUID |
| `ns_x500` | — | — | RFC 9562 X.500 namespace UUID |

**Namespaces for v5:** `dns`, `url`, `oid`, `x500`

**Formats for to_string:** `standard`, `hex`, `urn`, `binary`

Default action when no `action` field is present: `v7` (single UUID).

## Usage

**Via curl (direct to em_disco):**

```bash
# One UUID v7 (default)
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "uuid", "capabilities": ["alara_uuid"]}'

# Five UUID v7s
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"v7\",\"n\":5}", "capabilities": ["alara_uuid"]}'

# UUID v5 from DNS name
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"v5\",\"namespace\":\"dns\",\"name\":\"example.com\"}", "capabilities": ["alara_uuid"]}'

# Convert UUID to URN format
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"to_string\",\"uuid\":\"019d8079-604f-769b-8bb2-b9c4866f1030\",\"format\":\"urn\"}", "capabilities": ["alara_uuid"]}'

# DNS namespace UUID
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"ns_dns\"}", "capabilities": ["alara_uuid"]}'
```

**Via Erlang shell:**

```erlang
emquest_cli:query(<<"uuid">>).
emquest_cli:query(<<"{\"action\":\"v7\",\"n\":10}">>).
emquest_cli:query(<<"{\"action\":\"v5\",\"namespace\":\"url\",\"name\":\"https://example.com\"}">>).
```

## Installation

```bash
git clone https://github.com/EmergenceSystem/alara_uuid_filter.git
cd alara_uuid_filter
rebar3 shell --apps alara_uuid_filter
```

Requires `em_disco` running on `localhost:8080` (configured in `emergence.conf`).

## Capabilities

`search`, `query`, `alara_uuid`, `uuid`, `uuidv7`, `uuidv5`, `erlang`

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
