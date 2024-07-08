require "http"
require "json"
require "log"
require "redis"

module Dorsum
  class Events
    class Stream
      def initialize(@redis : Redis::PooledClient, @request : HTTP::Request)
      end

      def exist?
        Redis.new.exists(name) == 1
      end

      def name
        @request.path.split("/")[1]
      end

      def last_event_id
        return @request.headers["Last-Event-ID"] if @request.headers["Last-Event-ID"]?
        return @request.query_params["last-event-id"] if @request.query_params["last-event-id"]?

        nil
      end
    end

    class Source
      def initialize(@redis : Redis::PooledClient, @stream : String, @io : IO, @last_event_id : (String | Nil))
      end

      def stream
        Log.info { "Starting SSE for stream `#{@stream}'" }
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
          # We don't want to hog the CPU when there are no events to steam.
          sleep 2.seconds
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
        @redis = Redis::PooledClient.new
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
        stream = Stream.new(@redis, request)
        if stream.exist?
          response.content_type = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["Connection"] = "keep-alive"
          response.upgrade do |io|
            Source.new(@redis, stream.name, io, stream.last_event_id).stream
            io.close
          end
        else
          response.respond_with_status(HTTP::Status::NOT_FOUND)
        end
      end
    end
  end
end

server = HTTP::Server.new([
  HTTP::LogHandler.new,
  Dorsum::Events::Handler.new,
])
address = server.bind_tcp 9110
Log.info { "Listening on http://#{address}" }
server.listen
