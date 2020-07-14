#
# Copyright 2020 F5 Networks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'test_helper'

class BeaconOutputTest < Test::Unit::TestCase
  class TestBeaconOutput < Fluent::Plugin::BeaconOutput
    attr_reader :points
    attr_reader :req
    attr_reader :uri

    def configure(conf)
      @points = []
      super
    end

    def format(tag, time, record)
      super
    end

    def formatted_to_msgpack_binary
      super
    end

    def write(chunk)
      super
    end

    def write_points(points)
      @points << [points]
      super
    end

    def send_request(req, uri)
      @req = req
      @uri = uri
    end
  end

  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    source_name test-source-name
    token test-token
  ]

  def create_raw_driver(conf=CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::BeaconOutput).configure(conf)
  end

  def create_driver(conf=CONFIG)
    Fluent::Test::Driver::Output.new(TestBeaconOutput).configure(conf)
  end

  def test_configure
    driver = create_raw_driver %[
      source_name test-source-name
      token test-token
      endpoint https://localhost/beacon/v1/ingest-metrics
      token a-0123456789#fake-token
    ]
    assert_equal('https://localhost/beacon/v1/ingest-metrics', driver.instance.config['endpoint'])
    assert_equal('a-0123456789#fake-token', driver.instance.config['token'])
  end

  def test_configure_without_tag_chunk_key
    assert_raise(Fluent::ConfigError) do
      create_raw_driver %[
        source_name test-source-name
        token test-token
        <buffer arbitrary_key>
          @type memory
        </buffer>
      ]
    end
  end

  def test_configure_without_source
    assert_raise(Fluent::ConfigError) do
      create_raw_driver %[
        token test-token
      ]
    end
  end

  def test_configure_without_token
    assert_raise(Fluent::ConfigError) do
      create_raw_driver %[
        source_name test-source-name
      ]
    end
  end

  def test_format
    driver = create_driver(CONFIG)
    time = event_time('2011-01-02 13:14:15 UTC')

    driver.run(default_tag: 'test') do
      driver.feed(time, {'a' => 1,'b' => nil})
      driver.feed(time, {'a' => 2})
    end

    assert_equal [[to_ns(time), {'a' => 1}].to_msgpack,
                  [to_ns(time), {'a' => 2}].to_msgpack], driver.formatted
  end

  sub_test_case "#write" do
    test "buffer" do
      driver = create_driver(CONFIG)

      time = event_time("2011-01-02 13:14:15 UTC")
      driver.run(default_tag: 'input.influxdb') do
        driver.feed(time, {'a' => 1})
        driver.feed(time, {'a' => 2})
      end

      assert_equal([
        [
          [
            {
              timestamp: to_ns(time),
              series: 'input.influxdb',
              tags: {'beacon-fluent-source' => 'test-source-name'},
              values: {'a' => 1}
            },
            {
              timestamp: to_ns(time),
              series: 'input.influxdb',
              tags: {'beacon-fluent-source' => 'test-source-name'},
              values: {'a' => 2}
            },
          ]
        ]
      ], driver.instance.points)
    end
  end

  def test_write_with_measurement
    config_with_measurement = %Q(
      #{CONFIG}
      measurement test
    )

    driver = create_driver(config_with_measurement)

    time = event_time('2011-01-02 13:14:15 UTC')
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1})
      driver.feed(time, {'a' => 2})
    end

    assert_equal([
      [
        [
          {
            :timestamp => to_ns(time),
            :series    => 'test',
            :tags      => {'beacon-fluent-source' => 'test-source-name'},
            :values    => {'a' => 1}
          },
          {
            :timestamp => to_ns(time),
            :series    => 'test',
            :tags      => {'beacon-fluent-source' => 'test-source-name'},
            :values    => {'a' => 2}
          },
        ]
      ]
    ], driver.instance.points)

    assert_equal('https://ingestion.ovr.prd.f5aas.com:50443/beacon/v1/ingest-metrics', driver.instance.uri.to_s)
    assert_equal('test-token', driver.instance.req['X-F5-Ingestion-Token'])
    assert_equal('text/plain', driver.instance.req['Content-Type'])
    assert_equal("test,beacon-fluent-source=test-source-name a=1i 1293974055000000000\n" +
                 "test,beacon-fluent-source=test-source-name a=2i 1293974055000000000", driver.instance.req.body)
  end

  def test_empty_tag_keys
    config_with_tags = %Q(
      #{CONFIG}
      tag_keys ["b"]
    )

    driver = create_driver(config_with_tags)

    time = event_time("2011-01-02 13:14:15 UTC")
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1, 'b' => ''})
      driver.feed(time, {'a' => 2, 'b' => 1})
      driver.feed(time, {'a' => 3, 'b' => ' '})
    end

    assert_equal([
      [
        [
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 1},
            tags: {'beacon-fluent-source' => 'test-source-name'},
          },
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 2},
            tags: {'b' => 1, 'beacon-fluent-source' => 'test-source-name'},
          },
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 3},
            tags: {'beacon-fluent-source' => 'test-source-name'},
          },
        ]
      ]
    ], driver.instance.points)
  end

  def test_auto_tagging
    config_with_tags = %Q(
      #{CONFIG}

      auto_tags true
    )

    driver = create_driver(config_with_tags)

    time = event_time("2011-01-02 13:14:15 UTC")
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1, 'b' => '1'})
      driver.feed(time, {'a' => 2, 'b' => 1})
      driver.feed(time, {'a' => 3, 'b' => ' '})
    end

    assert_equal([
      [
        [
          {
            :timestamp => to_ns(time),
            :series    => 'input.influxdb',

            :values    => {'a' => 1},
            :tags      => {'b' => '1', 'beacon-fluent-source' => 'test-source-name'},
          },
          {
            :timestamp => to_ns(time),
            :series    => 'input.influxdb',
            :values    => {'a' => 2, 'b' => 1},
            :tags      => {'beacon-fluent-source' => 'test-source-name'},
          },
          {
            :timestamp => to_ns(time),
            :series    => 'input.influxdb',
            :values    => {'a' => 3},
            :tags      => {'beacon-fluent-source' => 'test-source-name'},
          },
        ]
      ]
    ], driver.instance.points)
  end

  def test_ignore_empty_values
    config_with_tags = %Q(
      #{CONFIG}

      tag_keys ["b"]
    )

    driver = create_driver(config_with_tags)

    time = event_time('2011-01-02 13:14:15 UTC')
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'b' => '3'})
      driver.feed(time, {'a' => 2, 'b' => 1})
    end

    assert_equal([
      [
        [
          {
            :timestamp => to_ns(time),
            :series    => 'input.influxdb',

            :values    => {'a' => 2},
            :tags      => {'b' => 1, 'beacon-fluent-source' => 'test-source-name'},
          }
        ]
      ]
    ], driver.instance.points)
  end

  def test_seq
    config = %[
      type beacon
      source_name test-source-name
      token test-token
      sequence_tag _seq
    ]
    driver = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    next_time = Fluent::EventTime.new(time + 1)
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1})
      driver.feed(time, {'a' => 2})

      driver.feed(next_time, {'a' => 1})
      driver.feed(next_time, {'a' => 2})
    end

    assert_equal([
      [
        [
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 1},
            tags: {'_seq' => 0, 'beacon-fluent-source' => 'test-source-name'},
          },
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 2},
            tags: {'_seq' => 1, 'beacon-fluent-source' => 'test-source-name'},
          },
          {
            timestamp: to_ns(time + 1),
            series: 'input.influxdb',
            values: {'a' => 1},
            tags: {'_seq' => 0, 'beacon-fluent-source' => 'test-source-name'},
          },
          {
            timestamp: to_ns(time + 1),
            series: 'input.influxdb',
            values: {'a' => 2},
            tags: {'_seq' => 1, 'beacon-fluent-source' => 'test-source-name'},
          }
        ]
      ]
    ], driver.instance.points)
  end

  def test_cast_number
    config = %Q(
      #{CONFIG}
      cast_number_to_float true
    )

    driver = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1})
    end

    assert_equal([
      [
        [
          {
            timestamp: to_ns(time),
            series: 'input.influxdb',
            values: {'a' => 1.0},
            tags: {'beacon-fluent-source' => 'test-source-name'},
          },
        ]
      ]
    ], driver.instance.points)
  end

  def test_time_key
    config = %Q(
    #{CONFIG}
      time_key b
    )

    driver = create_driver(config)

    time = event_time("2020-01-02 13:14:15 UTC")
    driver.run(default_tag: 'input.influxdb') do
      driver.feed(time, {'a' => 1, 'b' => 1293974055000000000})
    end

    assert_equal([
      [
        [
          {
            timestamp: 1293974055000000000,
            series: 'input.influxdb',
            values: {'a' => 1.0},
            tags: {'beacon-fluent-source' => 'test-source-name'},
          },
        ]
      ]
    ], driver.instance.points)
  end

  def to_ns(time)
    time * 1000000000
  end

end