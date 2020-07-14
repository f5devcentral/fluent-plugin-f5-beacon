![Ruby](https://github.com/f5devcentral/fluent-plugin-f5-beacon/workflows/Ruby/badge.svg) [![Gem Version](https://badge.fury.io/rb/fluent-plugin-f5-beacon.svg)](https://badge.fury.io/rb/fluent-plugin-f5-beacon)

# Fluent::Plugin::Beacon, a plugin for [Fluentd](http://fluentd.org)

fluent-plugin-f5-beacon is a buffered output plugin for Fluentd and F5 Beacon.

## Requirements

| fluent-plugin-f5-beacon | fluentd | ruby |
|------------------------|---------|------|
| * | >= v1.0.0  | >= 2.3 |

## Installation

    $ fluent-gem install fluent-plugin-f5-beacon

Alternatively, with td-agent:

    $ td-agent-gem install fluent-plugin-f5-beacon

Or via source (swap `td-agent-gem` for `fluent-gem` as needed):

    $ git clone https://github.com/f5devcentral/fluent-plugin-f5-beacon.git
    $ cd fluent-plugin-f5-beacon/
    $ fluent-gem build fluent-plugin-f5-beacon.gemspec
    $ fluent-gem install fluent-plugin-f5-beacon-#.#.#.gem

## Usage

Just like other regular output plugins, use type `f5-beacon` in your Fluentd configuration under `match` scope:

`@type` `f5_beacon`

--------------

**Options:**

`source_name`: The name of the source within Beacon.  This is required.

`token`: The Beacon ingestion token to be used.  This is required.

`measurement`: The measurement/series to use.  The default is nil.  If not specified, Fluentd's tag is used.

`time_key`: Use the value of this tag if it exists in the event instead of the event timestamp.

`auto_tags`: Enable/disable auto-tagging behavior which makes strings tags.  The default is false.

`tag_keys`: The names of the keys to use as tags instead of fields.

`sequence_tag`: The name of the tag whose value is incremented for the consecutive simultaneous events and reset to zero for a new event with the different timestamp.

`cast_number_to_float`: Enable/disable casting numbers to floats.  Within a measurement, a given field must be integer or float.  If your pipeline cannot unify the record value, this parameter may help avoid errors due to type conflicts.

## Configuration Example

```
<match mylog.*>
  @type f5_beacon
  source_name server1
  token a-123456789#token
  tag_keys ["key1", "key2"]
</match>
```

## Cache and multiprocess

The plugin is a buffered output plugin.  So additional buffer configuration (with default values) looks like:

```
<buffer>
  @type memory
  chunk_limit_size 524288 # 512 * 1024
  chunk_limit_records 1024
  flush_interval 60
  retry_limit 17
  retry_wait 1.0
  num_threads 1
</buffer>
```

Details around buffering can be found [here](https://docs.fluentd.org/buffer).

---

## Unit tests

```
bundle exec rake test
```
