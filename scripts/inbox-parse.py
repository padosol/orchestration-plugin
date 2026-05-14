#!/usr/bin/env python3
"""inbox.md 파서 — 단건 처리 모드 지원용.

inbox 메시지 블록 형식 (orch_append_message 가 만드는 것):
    \\n---\\nfrom: <wid>\\nto: <wid>\\nts: <iso>\\nid: <id>\\n---\\n<body>\\n

본문에 `---` 가 들어 있어도 깨지지 않도록, frontmatter 는 5줄 고정 패턴
(--- → from: → to: → ts: → id: → ---) 일 때만 메시지 시작으로 인식한다.

사용:
    inbox-parse.py summary <file>          한 건당 한 줄 (id\\treply\\tfrom\\tts\\tfirst50)
                                           reply: ● = 답신 필요, ○ = [답신 불필요] 마커
    inbox-parse.py reply-needed <file>     답신 필요 (●) 메시지 수만 출력
    inbox-parse.py ids <file>              id 목록만 (개행 구분)
    inbox-parse.py body <file> <id>        해당 메시지 frontmatter + 본문 출력
    inbox-parse.py extract <file> <id>     archive 에 append 할 raw 블록 (앞 \\n 포함)
    inbox-parse.py remove <file> <id>      해당 블록만 빼고 새 inbox 내용 stdout
"""
import sys


# 본문 끝에 이 마커가 있으면 답신 불필요로 간주. 없으면 default = 답신 필요.
NO_REPLY_MARKER = '**[답신 불필요]**'


def parse(text):
    """inbox 텍스트 → 메시지 리스트.

    각 메시지: dict(from, to, ts, id, body, block_start, body_end).
    block_start = '---' 라인 인덱스, body_end = (다음 메시지 시작 또는 EOF) exclusive.
    """
    lines = text.split('\n')
    msgs = []
    i = 0
    n = len(lines)
    while i < n:
        if lines[i] == '---' and i + 5 < n:
            fm = lines[i + 1:i + 5]
            if (fm[0].startswith('from: ') and
                    fm[1].startswith('to: ') and
                    fm[2].startswith('ts: ') and
                    fm[3].startswith('id: ') and
                    lines[i + 5] == '---'):
                body_start = i + 6
                body_end = body_start
                while body_end < n:
                    if (lines[body_end] == '---' and
                            body_end + 5 < n and
                            lines[body_end + 1].startswith('from: ') and
                            lines[body_end + 2].startswith('to: ') and
                            lines[body_end + 3].startswith('ts: ') and
                            lines[body_end + 4].startswith('id: ') and
                            lines[body_end + 5] == '---'):
                        break
                    body_end += 1
                msgs.append({
                    'from': fm[0][6:],
                    'to': fm[1][4:],
                    'ts': fm[2][4:],
                    'id': fm[3][4:],
                    'body': '\n'.join(lines[body_start:body_end]).rstrip('\n'),
                    'block_start': i,
                    'body_end': body_end,
                })
                i = body_end
                continue
        i += 1
    return msgs, lines


def cmd_summary(text):
    # 표시 순서 = 도착 순 (FIFO). 파일 append 순서를 그대로 보존 —
    # poll-inbox / check-inbox 모두 head -1 = 가장 오래된 메시지를 다음 처리 대상으로 가리킨다.
    # reply 컬럼: ● = 답신 필요 (default), ○ = [답신 불필요] 마커 본문에 있음.
    msgs, _ = parse(text)
    for m in msgs:
        first = m['body'].split('\n', 1)[0][:50]
        reply = '○' if NO_REPLY_MARKER in m['body'] else '●'
        print(f"{m['id']}\t{reply}\t{m['from']}\t{m['ts']}\t{first}")


def cmd_reply_needed(text):
    msgs, _ = parse(text)
    n = sum(1 for m in msgs if NO_REPLY_MARKER not in m['body'])
    print(n)


def cmd_ids(text):
    msgs, _ = parse(text)
    for m in msgs:
        print(m['id'])


def find_msg(text, msg_id):
    msgs, lines = parse(text)
    for m in msgs:
        if m['id'] == msg_id:
            return m, msgs, lines
    available = ', '.join(m['id'] for m in msgs) or '(없음)'
    sys.stderr.write(f"ERROR: id '{msg_id}' 미존재. 사용 가능 id: {available}\n")
    sys.exit(2)


def cmd_body(text, msg_id):
    m, _, _ = find_msg(text, msg_id)
    print(f"---\nfrom: {m['from']}\nto: {m['to']}\nts: {m['ts']}\nid: {m['id']}\n---")
    print(m['body'])


def cmd_extract(text, msg_id):
    m, _, _ = find_msg(text, msg_id)
    sys.stdout.write(
        f"\n---\nfrom: {m['from']}\nto: {m['to']}\nts: {m['ts']}\nid: {m['id']}\n---\n{m['body']}\n"
    )


def cmd_remove(text, msg_id):
    m, _, lines = find_msg(text, msg_id)
    start = m['block_start']
    # 블록 앞의 빈 줄 한 개도 함께 제거 (orch_append_message 가 \n--- 로 시작)
    if start > 0 and lines[start - 1] == '':
        start -= 1
    end = m['body_end']
    new_lines = lines[:start] + lines[end:]
    sys.stdout.write('\n'.join(new_lines))


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    cmd, path = sys.argv[1], sys.argv[2]
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except FileNotFoundError:
        sys.stderr.write(f"ERROR: 파일 없음: {path}\n")
        sys.exit(2)

    if cmd == 'summary':
        cmd_summary(text)
    elif cmd == 'reply-needed':
        cmd_reply_needed(text)
    elif cmd == 'ids':
        cmd_ids(text)
    elif cmd in ('body', 'extract', 'remove'):
        if len(sys.argv) < 4:
            sys.stderr.write(f"ERROR: '{cmd}' 는 <id> 인자 필요\n")
            sys.exit(2)
        msg_id = sys.argv[3]
        if cmd == 'body':
            cmd_body(text, msg_id)
        elif cmd == 'extract':
            cmd_extract(text, msg_id)
        else:
            cmd_remove(text, msg_id)
    else:
        sys.stderr.write(f"ERROR: 알 수 없는 명령 '{cmd}'\n")
        sys.exit(2)


if __name__ == '__main__':
    main()
