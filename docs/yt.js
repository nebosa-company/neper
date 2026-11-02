document.addEventListener('click', e => {
  const b = e.target.closest('button[data-yt]')
  if (!b) return
  const f = document.createElement('iframe')
  f.src = 'https://www.youtube-nocookie.com/embed/' + b.dataset.yt + '?rel=0&autoplay=1'
  f.title = b.dataset.title
  f.allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share'
  f.referrerPolicy = 'strict-origin-when-cross-origin'
  f.allowFullscreen = true
  f.className = b.className.replace('yt', '').trim()
  b.replaceWith(f)
  f.focus()
})
