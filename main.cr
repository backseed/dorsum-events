require "http"
require "json"
require "log"
require "redis"

module Dorsum
  class Events
    class Source
      STREAM = "distantcacophony"

      def initialize(@io : IO, @last_event_id : (String | Nil))
        Log.info { "Events starting at #{@last_event_id}" } if @last_event_id
        @redis = Redis.new
      end

      def stream
        loop do
          start = @last_event_id ? @last_event_id : "0-0"
          stream_streams(
            @redis.command([
              "XREAD",
              "BLOCK", "5000",
              "STREAMS", STREAM, start,
            ]).as(Array(Redis::RedisValue))
          )
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
        if acceptable_request?(request)
          handle_request(request, context.response)
        elsif path =~ /^\/([\w]+)$/
          context.request.path = "/index.html"
          @static_handler.call(context)
        else
          call_next(context)
        end
      end

      private def acceptable_request?(request)
        request.headers["Accept"]? == "text/event-stream"
      end

      private def handle_request(request, response)
        response.content_type = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["Connection"] = "keep-alive"
        response.upgrade do |io|
          Source.new(io, last_event_id(request)).stream
          io.close
        end
      end

      private def last_event_id(request)
        return request.headers["Last-Event-ID"] if request.headers["Last-Event-ID"]?
        pp request.query_params
        return request.query_params["last-event-id"] if request.query_params["last-event-id"]?

        "0-0"
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
