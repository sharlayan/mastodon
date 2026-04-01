var NAMESPACE = 'emoji-mart'

var isLocalStorageSupported =
  typeof window !== 'undefined' && 'localStorage' in window

let getter
let setter

function setHandlers(handlers) {
  if (!handlers) {
    handlers = {}
  }

  getter = handlers.getter
  setter = handlers.setter
}

function setNamespace(namespace) {
  NAMESPACE = namespace
}

function update(state) {
  for (let key in state) {
    let value = state[key]
    set(key, value)
  }
}

function set(key, value) {
  if (setter) {
    setter(key, value)
  } else {
    if (!isLocalStorageSupported) return
    try {
      window.localStorage[`${NAMESPACE}.${key}`] = JSON.stringify(value)
    } catch (e) {}
  }
}

function get(key) {
  if (getter) {
    return getter(key)
  }

  if (!isLocalStorageSupported) {
    return undefined
  }

  try {
    var value = window.localStorage[`${NAMESPACE}.${key}`]

    if (value) {
      return JSON.parse(value)
    }
    return undefined
  } catch (e) {
    return undefined
  }
}

const utilStore = { update, set, get, setNamespace, setHandlers }

export default utilStore
