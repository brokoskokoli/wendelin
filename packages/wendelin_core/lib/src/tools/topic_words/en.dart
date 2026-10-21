/// English topic words per integration id (alphabetical). See README.md.
const topicWordsEn = <String, List<String>>{
  'alarms': [
    'alarm', 'wake me', 'wake up', 'get up', 'timer', 'stopwatch', //
    'countdown', 'set an alarm', 'snooze',
  ],
  'bring': [
    'bring', 'shopping', 'groceries', 'grocery', 'shopping list', //
    'buy', 'supermarket', 'add to the list',
  ],
  'calendar': [
    'calendar', 'appointment', 'agenda', 'meeting', 'event', //
    'schedule', 'birthday', 'dentist', 'what s on', 'my day',
  ],
  'clipboard': [
    'clipboard', 'copy', 'paste', 'copied', 'what did i copy', //
  ],
  'contacts': [
    'contact', 'phone number', 'mobile number', 'call', 'ring', //
    'text', 'sms', 'message', 'address book', 'dial', 'whatsapp',
  ],
  'flashlight': [
    'flashlight', 'torch', 'light on', 'light off', 'lamp on', //
    'lamp off', 'flash',
  ],
  'gtasks': [
    'google tasks', 'task', 'todo', 'to do', 'due', 'overdue', //
    'remind', 'errand',
  ],
  'ha': [
    'home assistant', 'smart home', 'heating', 'light', 'lamp', //
    'socket', 'plug', 'thermostat', 'blinds', 'shutter', 'switch',
    'living room', 'bedroom', 'fan', 'turn on', 'turn off',
  ],
  'lists': [
    'list', 'lists', 'packing list', 'put on', 'cross off', //
    'shopping list', 'wish list', 'checklist', 'add to my',
  ],
  'location': [
    'location', 'where am i', 'position', 'my address', //
    'current place', 'gps', 'coordinates', 'nearby',
  ],
  'maps': [
    'route', 'navigate', 'navigation', 'map', 'directions', //
    'how do i get', 'drive to', 'distance', 'google maps', 'how far',
    'travel time',
  ],
  'media': [
    'pause', 'resume playback', 'volume', 'louder', 'quieter', //
    'next track', 'previous track', 'play', 'skip', 'stop the music',
    'mute', 'turn it up', 'turn it down', 'what s playing',
  ],
  'memory': [
    'remember', 'memory', 'forget', 'do you remember', 'i told you', //
    'keep in mind', 'note for yourself',
  ],
  'obsidian': [
    'obsidian', 'note', 'notes', 'vault', 'journal', 'diary', 'memo', //
    'jot down', 'write down', 'entry',
  ],
  'spotify': [
    'spotify', 'music', 'song', 'playlist', 'album', 'artist', //
    'listen to', 'podcast', 'radio', 'put on some',
  ],
  'station': [
    'station mode', 'station', 'charging station', 'desk mode', //
    'bedside', 'photo frame',
  ],
  'tasks': [
    'task', 'due', 'overdue', 'todo', 'to do', 'remind', 'errand', //
    'tick off', 'to dos',
  ],
  'todoist': [
    'todoist', 'task', 'due', 'overdue', 'todo', 'to do', 'remind', //
    'project',
  ],
  'weather': [
    'weather', 'rain', 'temperature', 'forecast', 'snow', 'sunny', //
    'storm', 'wind', 'how warm', 'how cold', 'umbrella', 'degrees',
  ],
  'web': [
    'internet', 'web', 'google', 'search the web', 'look up', //
    'online', 'wikipedia', 'news', 'find out',
  ],
};
