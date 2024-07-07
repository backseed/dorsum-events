# Dorsum-events

Listens to Redis Streams and forwards them to an HTTP client using server-sent events.

The SSE can be requested by setting the `Accept` header to `text/event-stream` and then requesting the channel in the request path.

For example, when the channel is `moths` you can test with the following:

    curl -H "Accept: text/event-stream" http://localhost:9110/moths

When you want to start the stream from a specific event id, you can either set it throught the `last-event-id` query parameter or the `Last-Event-ID` request header.

    curl -H "Accept: text/event-stream" http://localhost:9110/moths?last-event-id=1675014118178-0

## Redis Stream assumptions

We make a few assumptions to the Redis Stream to simplify the implementation. The name of the field in the stream is the event type and the value should be a single String. Usually that means a JSON document.

    XADD moths * individuals '{"name":"yellow"}'

Will translate to an SSE that looks something like this:

    id: 1675018066245-0
    event: individuals
    data: {"name":"yellow"}

## Future

* Automated trimming and using XRANGE with COUNT on requests without a last-event-id to keep performance acceptable.

## Setup

Setting up is probably easiest in Caddy.

```
example.com {
  proxy / http://localhost:9110 {
    flush_interval -1 # turn off request buffering
  }
}
```
