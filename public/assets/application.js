(function() {
  const arrivals = document.getElementById('arrivals')
  const template = document.getElementById('arrival')
  const offset = new Date().getTimezoneOffset()

  const event_source = new EventSource(window.location.href)
  event_source.addEventListener('arrival', (event) => {
    const data = JSON.parse(event.data)
    const arrival = template.content.cloneNode(true)

    arrival.querySelectorAll('a').forEach((element) => {
      if (data['color']) element.style.color = data['color']
      element.appendChild(document.createTextNode(' '))
      element.appendChild(document.createTextNode(data['display-name']))
      element.href = "?last-event-id=" + event.lastEventId
    })
    if (data['arrived-at']) {
      var arrival_at = new Date(data['arrived-at'])
      arrival_at = new Date(arrival_at - arrival_at.getTimezoneOffset() - offset)
      arrival.querySelectorAll('span').forEach((element) => {
        element.appendChild(document.createTextNode(
          arrival_at.getHours() + ':' + arrival_at.getMinutes()
        ))
      })
    }
    
    arrivals.appendChild(arrival)
  })
})()
