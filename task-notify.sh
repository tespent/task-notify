#!/bin/bash
# -*- coding=utf-8 -*-

#
#  Copyright (c) @tespent (https://github.com/tespent)
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

''':'
PYTHON="$(command -v python3)"
[[ -z "$PYTHON" ]] && PYTHON="$(command -v python)"
[[ -z "$PYTHON" ]] && PYTHON="$(command -v python2)"
[[ -z "$PYTHON" ]] && (echo "Python not found, please install python first" && exit 1)

PYTHON_VER="$("$PYTHON" -c 'import sys;print(sys.version_info.major)')"
[[ "$PYTHON_VER" = 3 ]] || (echo "Only Python 3.x is supported, please install python first" && exit 1)

declare -a python_cmd=("$PYTHON" "$0")

LOGROOT=${LOGROOT:-/tmp}

LOGDIR="$(mktemp -d longtask-XXXXXXXXXXXX -p "$LOGROOT")"

USE_TTY=1

# usage: emit_message filename
emit_message() {
	curl -X POST -H 'Content-Type: application/json' https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxxxxxxxxxxxxxx -T "$1"
	#curl -X POST -H "Authorization: Bearer xxxxxxxxxxxxxxxxxxx" -H "Content-Type: application/json" http://10.xx.xx.xx:12345/send_text -T "$1"

	echo ""
}

gather_stdout() {
	(tee /dev/stderr > "$LOGDIR/stdout") 2>&1
}

gather_stderr() {
	tee /dev/stderr > "$LOGDIR/stderr"
}

run() {
	if [[ ! $USE_TTY = 0 ]]; then
		declare -a cmd=("$@")
		{
			echo "#!$BASH"
			declare -p cmd
			echo 'exec "${cmd[@]}"'
		} > "$LOGDIR/command.sh"
		chmod +x "$LOGDIR/command.sh"
		{
			time script -e -c "$LOGDIR/command.sh" -t"$LOGDIR/timing" "$LOGDIR/output"
		} 2>"$LOGDIR/time"
		return $?
	else
		{
			time {
				("$@" 2> >(gather_stderr) > >(gather_stdout) ) 2>&3
			}
		} 3>&2 2>"$LOGDIR/time"
		return $?
	fi
}

date '+%s.%N' > "$LOGDIR/start"

run "$@"
CODE=$?

date '+%s.%N' > "$LOGDIR/end"

cat "$LOGDIR/time"

echo "Log saved at $LOGDIR"

"${python_cmd[@]}" "$CODE" "$LOGDIR" "$USE_TTY" "$@" > "$LOGDIR/stat.json" && emit_message "$LOGDIR/stat.json"

#rm -f "$TIME_FILE" "$LOG_FILE" "$ERR_FILE"

exit $CODE

''' #'''

import os
import re
import sys
import time
import json
import platform

def lastlines(fn, nlines=20, seeksize=16384):
  with open(fn, 'rb') as f:
    try:
      f.seek(-1, os.SEEK_END)
    except OSError:
      return []

    ch = f.read(1)
    strip_end = 0
    while ch in [b'\r', b'\n']:
      strip_end += 1
      try:
        f.seek(-2, os.SEEK_CUR)
        ch = f.read(1)
      except OSError:
        return []

    try:  # catch OSError in case of a one line file 
      f.seek(-seeksize, os.SEEK_CUR)
      chunk = f.read(seeksize)
    except OSError:
      f.seek(0)
      chunk = f.read(seeksize)[:-strip_end]

    lines = []
    pos = len(chunk)
    while nlines > 0:
      new_pos = chunk.rfind(b'\n', 0, pos)
      nlines -= 1
      lines.append(chunk[new_pos+1:pos].decode())
      pos = new_pos
      if pos < 0:
        break
    lines.reverse()
    return lines

    last_line = f.readline().decode()

def filecontent(fn):
  with open(fn, 'r') as f:
    return f.readline()

if len(sys.argv) < 3:
  print('You can not run this script with python directly! execute with bash instead.')
  sys.exit(1)

code = int(sys.argv[1])
logdir = sys.argv[2]
usetty = int(sys.argv[3])
cmd = sys.argv[4:]

def lastlog(ty, **kwargs):
  lines = lastlines(os.path.join(logdir, ty), **kwargs)
  lines = map(lambda v: re.sub('\x1b\[[0-9;]*m', '', v), lines)
  lines = map(lambda v: re.sub('\x1b\[0?K', '', v), lines)
  lines = map(lambda v: v.strip(), lines)
  lines = map(lambda v: v[v.rfind('\r')+1:], lines)
  return lines
def ts(ty):
  return time.strftime('%F %T %z', time.localtime(float(filecontent(os.path.join(logdir, ty)))))

if code == 0:
  status = 'SUCCESS'
  status_color = 'green'
else:
  status = 'FAILED'
  status_color = 'red'

obj = {
  "config": {
    "wide_screen_mode": True
  },
  "header": {
    "template": status_color,
    "title": {
      "content": "{}: Command exited with code {}".format(status, code),
      "tag": "plain_text"
    }
  },
  "elements": [
    {
      "fields": [
        {
          "is_short": False,
          "text": {
            "content": "<at id=all></at>",
            "tag": "lark_md"
          }
        },
        {
          "is_short": False,
          "text": {
            "content": "**📝 Command:**\n{}".format(' '.join(cmd)),
            "tag": "lark_md"
          }
        },
        {
          "is_short": False,
          "text": {
            "content": "",
            "tag": "lark_md"
          }
        },
        {
          "is_short": True,
          "text": {
            "content": "**🕐 Start time:**\n{}".format(ts('start')),
            "tag": "lark_md"
          }
        },
        {
          "is_short": True,
          "text": {
            "content": "**🕐 End time:**\n{}".format(ts('end')),
            "tag": "lark_md"
          }
        },
        {
          "is_short": False,
          "text": {
            "content": "",
            "tag": "lark_md"
          }
        },
        {
          "is_short": True,
          "text": {
          "content": "**Node name:**\n{}\n**Exit code:**\n{}".format(platform.node(), code),
            "tag": "lark_md"
          }
        },
        {
          "is_short": True,
          "text": {
            "content": "**Time cost:**\n{}".format('\n'.join(lastlog('time')).strip()),
            "tag": "lark_md"
          }
        },
      ],
      "tag": "div"
    },
    {
      "tag": "note",
      "elements": [
        {
          "tag": "plain_text",
          "content": "Full log saved at {}".format(logdir)
        }
      ]
    }
  ]
}

def addlog(obj, name, nlines=20):
  obj['elements'].extend([
    {
      "tag": "hr"
    },
    {
      "tag": "div",
      "text": {
        "tag": "lark_md",
        "content": "**📋 Last {} line from {}:**".format(nlines, name)
      }
    },
    {
      "tag": "div",
      "text": {
        "tag": "plain_text",
        "content": '\n'.join(lastlog(name, nlines=nlines)),
      }
    }
  ])

if usetty == 0:
  addlog(obj, 'stdout')
  addlog(obj, 'stderr')
else:
  addlog(obj, 'output')

print(json.dumps({
  'msg_type': 'interactive',
  'card': obj,
}))
