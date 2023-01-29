require "http"
require "json"
require "log"
require "redis"

module Dorsum
  class Events
    class Source
      def initialize(@stream : String, @io : IO, @last_event_id : (String | Nil))
        Log.info { "Starting SSE for stream #{@stream}" }
        @redis = Redis.new
      end

      def stream
        loop do
          if @last_event_id
            stream_streams(
              @redis.command([
                "XREAD",
                "BLOCK", "5000",
                "STREAMS", @stream, @last_event_id,
              ]).as(Array(Redis::RedisValue))
            )
          else
            stream_events(
              @redis.command(
                ["XREVRANGE", @stream, "+", "-", "COUNT", "64"]
              ).as(Array(Redis::RedisValue)).reverse
            )
          end
        end
      end

      def stream_streams(streams : Array(Redis::RedisValue))
        streams.each { |stream| stream_stream(stream.as(Array(Redis::RedisValue))) }
      end

      def stream_stream(stream : Array(Redis::RedisValue))
        stream_events(stream[1].as(Array(Redis::RedisValue)))
      end

      def stream_events(events : Array(Redis::RedisValue))
        events.each { |event| stream_event(event.as(Array(Redis::RedisValue))) }
      end

      def stream_event(event : Array(Redis::RedisValue))
        @last_event_id = event[0].as(String)
        details = event[1].as(Array(Redis::RedisValue))
        @io.puts "id: #{@last_event_id}"
        @io.puts "event: #{details[0]}"
        @io.puts "data: #{details[1]}"
        @io.puts
        @io.flush
      end
    end

    class Handler
      include HTTP::Handler

      def initialize
        @static_handler = HTTP::StaticFileHandler.new("public", false, true)
      end

      def call(context)
        request = context.request
        path = context.request.path
        if path =~ /^\/([\w]+)$/
          handle_request(request, context.response)
        else
          call_next(context)
        end
      end

      private def handle_request(request, response)
        response.content_type = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["Connection"] = "keep-alive"
        response.upgrade do |io|
          Source.new(stream(request), io, last_event_id(request)).stream
          io.close
        end
      end

      private def stream(request)
        request.path.split("/")[1]
      end

      private def last_event_id(request)
        return request.headers["Last-Event-ID"] if request.headers["Last-Event-ID"]?
        return request.query_params["last-event-id"] if request.query_params["last-event-id"]?

        nil
      end
    end
  end
end

server = HTTP::Server.new([
  HTTP::LogHandler.new,
  Dorsum::Events::Handler.new,
  HTTP::StaticFileHandler.new("public", false, false),
])
address = server.bind_tcp 9110
Log.info { "Listening on http://#{address}" }
server.listen
