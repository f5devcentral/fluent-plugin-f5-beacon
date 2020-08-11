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

# encoding: UTF-8
require 'date'
require 'fluent/mixin'
require 'fluent/plugin/output'
require 'influxdb'
require 'net/http'
require 'openssl'
require 'uri'

module Fluent::Plugin class BeaconOutput < Output
  Fluent::Plugin.register_output('f5_beacon', self)

  helpers :compat_parameters

  DEFAULT_BUFFER_TYPE = "memory"

  config_param :endpoint, :string, default: 'https://ingestion.ovr.prd.f5aas.com:50443/beacon/v1/ingest-metrics',
               desc: "The target endpoint for sending data."
  config_param :token, :string, desc: "The Beacon access token.  This is a required field."
  config_param :source_name, :string, desc: "The source name shown in Beacon.  This is a required field."
  config_param :measurement, :string, default: nil,
               desc: "The measurement name to insert event.  If not specified, fluentd's tag is used."
  config_param :time_key, :string, default: 'time',
               desc: 'Use value of this tag if it exists in event instead of event timestamp.'
  config_param :auto_tags, :bool, default: false,
               desc: "Enable/disable auto-tagging behavior which makes strings tags."
  config_param :tag_keys, :array, default: [],
               desc: "The names of the keys to use as tags."
  config_param :sequence_tag, :string, default: nil,
               desc: <<-DESC
The name of the tag whose value is incremented for the consecutive simultaneous
events and reset to zero for a new event with the different timestamp.
  DESC
  config_param :cast_number_to_float, :bool, default: false,
               desc: "Enable/disable casting numbers to float."

  config_section :buffer do
    config_set_default :@type, DEFAULT_BUFFER_TYPE
    config_set_default :chunk_keys, ['tag']
  end

  def initialize
    super
    @seq = 0
    @prev_timestamp = nil
  end

  def configure(conf)
    compat_parameters_convert(conf, :buffer)
    super
    raise Fluent::ConfigError, "'tag' in chunk_keys is required." if not @chunk_key_tag
  end

  def start
    super
    log.info "starting F5 Beacon plugin..."
  end

  FORMATTED_RESULT_FOR_INVALID_RECORD = ''.freeze

  def format(tag, time, record)
    # Remove nil/empty values
    record.delete_if { |k, v| v.nil? || v.to_s.empty? }

    if record.empty?
      log.warn "skip record '#{record}' in '#{tag}', because record has no values"
      FORMATTED_RESULT_FOR_INVALID_RECORD
    else
      [precision_time(time), record].to_msgpack
    end
  end

  def shutdown
    super
  end

  def formatted_to_msgpack_binary
    true
  end

  def multi_workers_ready?
    true
  end

  def write(chunk)
    points = []
    tag = chunk.metadata.tag
    chunk.msgpack_each do |time, record|
      timestamp = record.delete(@time_key) || time
      if tag_keys.empty? && !@auto_tags
        values = record
        tags = {}
      else
        values = {}
        tags = {}
        record.each_pair do |k, v|
          if (@auto_tags && v.is_a?(String)) || @tag_keys.include?(k)
            # If the tag value is not nil, empty, or a space, add the tag
            normalized_value = v.to_s.strip
            if normalized_value != ''
              tags[k] = normalized_value
            end
          else
            values[k] = v
          end
        end
      end

      if @sequence_tag
        if @prev_timestamp == timestamp
          @seq += 1
        else
          @seq = 0
        end
        tags[@sequence_tag] = @seq
        @prev_timestamp = timestamp
      end

      values.delete_if do |k, v|
        if v.is_a?(Array) || v.is_a?(Hash)
          log.warn "array/hash field '#{k}' discarded; consider using a plugin to map"
          true
        end
      end

      if values.empty?
        log.warn "skip record '#{record}', because one value is required"
        next
      end

      if @cast_number_to_float
        values.each do |key, value|
          if value.is_a?(Integer)
            values[key] = Float(value)
          end
        end
      end

      tags["beacon-fluent-source"] = @source_name

      point = {
          timestamp: timestamp,
          series: @measurement || tag,
          values: values,
          tags: tags,
      }
      points << point
    end

    if points.length > 0
      write_points(points)
    end
  end

  def write_points(points)
    payload = serialize(points)
    handle_payload(payload)
  end

  def serialize(points)
    points.map do |point|
      InfluxDB::PointValue.new(point).dump
    end.join("\n".freeze)
  end

  def precision_time(time)
    # nsec is supported from v0.14
    time * (10 ** 9) + (time.is_a?(Integer) ? 0 : time.nsec)
  end

  def handle_payload(payload)
    req, uri = create_request(payload)
    send_request(req, uri)
  end

  def create_request(payload)
    uri = URI.parse(@endpoint)

    req = Net::HTTP.const_get("Post").new(uri.request_uri)
    req['X-F5-Ingestion-Token'] = @token
    req['Content-Type'] = 'text/plain'
    req.body = payload

    return req, uri
  end

  def send_request(req, uri)
    res = nil

    begin
      res = Net::HTTP.start(uri.host, uri.port, **http_opts(uri)) {|http| http.request(req) }

    rescue => e # rescue all StandardErrors
      # server didn't respond
      log.warn "Net::HTTP.#{req.method.capitalize} raises exception: #{e.class}, '#{e.message}'"
      raise e
    else
      unless res and res.is_a?(Net::HTTPSuccess)
        res_summary = if res
                        "#{res.code} #{res.message} #{res.body}"
                      else
                        "res=nil"
                      end
        log.warn "failed to #{req.method} #{uri} (#{res_summary})"
      end #end unless
    end # end begin
  end # end send_request

  def http_opts(uri)
    opts = {
        :use_ssl => true,
        :verify_mode => OpenSSL::SSL::VERIFY_PEER,
        :ssl_version => :TLSv1_2,
        :ciphers => ['AES128-GCM-SHA256', 'AES128-SHA256', 'AES256-GCM-SHA384', 'AES256-SHA256', 'ECDHE-RSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES128-SHA256', 'ECDHE-RSA-AES256-GCM-SHA384', 'ECDHE-RSA-AES256-SHA384'],
    }
    opts
  end

end
end
