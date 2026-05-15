#!/usr/bin/env python3
"""inbox 파서 — 메시지당 포인터 파일 모델.

inbox 는 디렉터리. 각 메시지 = 포인터 JSON + payload 본문 파일:
    <inbox_dir>/<nano>-<id>.json   = {"from","to","ts","id","payload"}
    <inbox_dir>/payloads/<id>.md   = 본문 raw

포인터 파일명의 nano prefix 로 정렬 = 도착 순(FIFO).

사용:
    inbox-parse.py summary <dir>           한 건당 한 줄 (id\\treply\\tfrom\\tts\\tfirst50)
                                           reply: ● = 답신 필요, ○ = [답신 불필요] 마커
    inbox-parse.py reply-needed <dir>      답신 필요 (●) 메시지 수만 출력
    inbox-parse.py ids <dir>               id 목록만 (개행 구분)
    inbox-parse.py body <dir> <id>         해당 메시지 frontmatter + 본문 출력
    inbox-parse.py extract <dir> <id>      archive 에 append 할 raw 블록 (앞 \\n 포함)
    inbox-parse.py remove <dir> <id>       해당 포인터+payload 삭제
    inbox-parse.py find-marker <dir> <s>   본문에 문자열 s 포함하는 첫 메시지 id
"""
import glob
import json
import os
import sys

# 본문 끝에 이 마커가 있으면 답신 불필요로 간주. 없으면 default = 답신 필요.
NO_REPLY_MARKER = '**[답신 불필요]**'


def load_dir(path):
    """inbox 디렉터리 → 메시지 리스트 (FIFO).

    각 메시지: dict(from, to, ts, id, body, pointer, payload).
    포인터 파일명 정렬 = nano prefix 순 = 도착 순.
    """
    msgs = []
    if not os.path.isdir(path):
        return msgs
    for ptr in sorted(glob.glob(os.path.join(path, '*.json'))):
        try:
            with open(ptr, 'r', encoding='utf-8') as f:
                meta = json.load(f)
        except (OSError, ValueError):
            continue
        payload = meta.get('payload', '')
        body = ''
        if payload:
            try:
                with open(payload, 'r', encoding='utf-8', errors='replace') as f:
                    body = f.read().rstrip('\n')
            except OSError:
                body = ''
        msgs.append({
            'from': meta.get('from', ''),
            'to': meta.get('to', ''),
            'ts': meta.get('ts', ''),
            'id': meta.get('id', ''),
            'body': body,
            'pointer': ptr,
            'payload': payload,
        })
    return msgs


def cmd_summary(msgs):
    for m in msgs:
        first = m['body'].split('\n', 1)[0][:50]
        reply = '○' if NO_REPLY_MARKER in m['body'] else '●'
        print(f"{m['id']}\t{reply}\t{m['from']}\t{m['ts']}\t{first}")


def cmd_reply_needed(msgs):
    n = sum(1 for m in msgs if NO_REPLY_MARKER not in m['body'])
    print(n)


def cmd_ids(msgs):
    for m in msgs:
        print(m['id'])


def find_msg(msgs, msg_id):
    for m in msgs:
        if m['id'] == msg_id:
            return m
    available = ', '.join(m['id'] for m in msgs) or '(없음)'
    sys.stderr.write(f"ERROR: id '{msg_id}' 미존재. 사용 가능 id: {available}\n")
    sys.exit(2)


def cmd_body(msgs, msg_id):
    m = find_msg(msgs, msg_id)
    print(f"---\nfrom: {m['from']}\nto: {m['to']}\nts: {m['ts']}\nid: {m['id']}\n---")
    print(m['body'])


def cmd_extract(msgs, msg_id):
    m = find_msg(msgs, msg_id)
    sys.stdout.write(
        f"\n---\nfrom: {m['from']}\nto: {m['to']}\nts: {m['ts']}\nid: {m['id']}\n---\n{m['body']}\n"
    )


def cmd_remove(msgs, msg_id):
    m = find_msg(msgs, msg_id)
    for p in (m['pointer'], m['payload']):
        if p and os.path.exists(p):
            try:
                os.remove(p)
            except OSError as e:
                sys.stderr.write(f"ERROR: 삭제 실패 {p}: {e}\n")
                sys.exit(2)


def cmd_find_marker(msgs, marker):
    for m in msgs:
        if marker in m['body']:
            print(m['id'])
            return


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    cmd, path = sys.argv[1], sys.argv[2]
    msgs = load_dir(path)

    if cmd == 'summary':
        cmd_summary(msgs)
    elif cmd == 'reply-needed':
        cmd_reply_needed(msgs)
    elif cmd == 'ids':
        cmd_ids(msgs)
    elif cmd in ('body', 'extract', 'remove', 'find-marker'):
        if len(sys.argv) < 4:
            sys.stderr.write(f"ERROR: '{cmd}' 는 인자 필요\n")
            sys.exit(2)
        arg = sys.argv[3]
        if cmd == 'body':
            cmd_body(msgs, arg)
        elif cmd == 'extract':
            cmd_extract(msgs, arg)
        elif cmd == 'remove':
            cmd_remove(msgs, arg)
        else:
            cmd_find_marker(msgs, arg)
    else:
        sys.stderr.write(f"ERROR: 알 수 없는 명령 '{cmd}'\n")
        sys.exit(2)


if __name__ == '__main__':
    main()
