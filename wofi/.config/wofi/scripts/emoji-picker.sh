#!/bin/bash
# Emoji picker using wofi
# Reads emoji list and copies selection to clipboard

EMOJI_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/wofi/emoji-list.txt"

# Generate emoji list if it doesn't exist
if [ ! -f "$EMOJI_FILE" ]; then
  mkdir -p "$(dirname "$EMOJI_FILE")"
  cat > "$EMOJI_FILE" << 'EMOJIS'
😀 grinning face
😁 beaming face
😂 face with tears of joy
🤣 rolling on the floor laughing
😃 grinning face with big eyes
😄 grinning face with smiling eyes
😅 grinning face with sweat
😆 grinning squinting face
😉 winking face
😊 smiling face with smiling eyes
😋 face savoring food
😎 smiling face with sunglasses
😍 smiling face with heart-eyes
😘 face blowing a kiss
🥰 smiling face with hearts
😗 kissing face
😙 kissing face with smiling eyes
🥲 smiling face with tear
😚 kissing face with closed eyes
😜 winking face with tongue
🤪 zany face
😝 squinting face with tongue
🤑 money-mouth face
🤗 hugging face
🤭 face with hand over mouth
🫢 face with open eyes and hand over mouth
🫣 face with peeking eye
🤫 shushing face
🤔 thinking face
🫡 saluting face
🤐 zipper-mouth face
🤨 face with raised eyebrow
😐 neutral face
😑 expressionless face
😶 face without mouth
🫥 dotted line face
😏 smirking face
😒 unamused face
🙄 face with rolling eyes
😬 grimacing face
🤥 lying face
😌 relieved face
😔 pensive face
😪 sleepy face
🤤 drooling face
😴 sleeping face
😷 face with medical mask
🤒 face with thermometer
🤕 face with head-bandage
🤢 nauseated face
🤮 face vomiting
🤧 sneezing face
🥵 hot face
🥶 cold face
🥴 woozy face
😵 face with crossed-out eyes
🤯 exploding head
🤠 cowboy hat face
🥳 partying face
🥸 disguised face
😎 smiling face with sunglasses
🤓 nerd face
🧐 face with monocle
😕 confused face
🫤 face with diagonal mouth
😟 worried face
🙁 slightly frowning face
☹️ frowning face
😮 face with open mouth
😯 hushed face
😲 astonished face
😳 flushed face
🥺 pleading face
🥹 face holding back tears
😦 frowning face with open mouth
😧 anguished face
😨 fearful face
😰 anxious face with sweat
😥 sad but relieved face
😢 crying face
😭 loudly crying face
😱 face screaming in fear
😖 confounded face
😣 persevering face
😞 disappointed face
😓 downcast face with sweat
😩 weary face
😫 tired face
🥱 yawning face
😤 face with steam from nose
😡 enraged face
😠 angry face
🤬 face with symbols on mouth
👍 thumbs up
👎 thumbs down
👏 clapping hands
🙌 raising hands
🤝 handshake
🙏 folded hands
✌️ victory hand
🤞 crossed fingers
🤟 love-you gesture
🤘 sign of the horns
👌 OK hand
🤌 pinched fingers
👋 waving hand
💪 flexed biceps
❤️ red heart
🧡 orange heart
💛 yellow heart
💚 green heart
💙 blue heart
💜 purple heart
🖤 black heart
🤍 white heart
💯 hundred points
💥 collision
💫 dizzy
💦 sweat droplets
🔥 fire
✨ sparkles
🌟 glowing star
⭐ star
🎉 party popper
🎊 confetti ball
🎈 balloon
💎 gem stone
🏆 trophy
🥇 1st place medal
🥈 2nd place medal
🥉 3rd place medal
⚡ high voltage
💡 light bulb
🔑 key
🔒 locked
🔓 unlocked
🔔 bell
📌 pushpin
📎 paperclip
✏️ pencil
📝 memo
📁 file folder
📂 open file folder
📊 bar chart
📈 chart increasing
📉 chart decreasing
🔍 magnifying glass tilted left
🔎 magnifying glass tilted right
💻 laptop
🖥️ desktop computer
⌨️ keyboard
🖱️ computer mouse
🌐 globe with meridians
🚀 rocket
✅ check mark button
❌ cross mark
⚠️ warning
ℹ️ information
❓ question mark
❗ exclamation mark
➕ plus
➖ minus
✖️ multiply
➗ divide
♻️ recycling symbol
🔄 counterclockwise arrows button
⏰ alarm clock
⏳ hourglass not done
🕐 one o'clock
📅 calendar
🗓️ spiral calendar
EMOJIS
fi

# Show picker
selected=$(cat "$EMOJI_FILE" | wofi --dmenu --prompt "Emoji" --cache-file /dev/null --width 400 --height 500)

if [ -n "$selected" ]; then
  # Extract just the emoji character (first field)
  emoji=$(echo "$selected" | cut -d' ' -f1)
  echo -n "$emoji" | wl-copy
  notify-send -t 2000 "Copied" "$emoji"
fi
