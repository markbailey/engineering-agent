#!/usr/bin/env bash
# dependency-graph.sh — Visualize ticket dependency graph
# Args: $1=ticket_id [--json|--ascii|--dot]
# Reads linked_issues from runs/{ticket_id}/ticket.json if available
# Output: dependency graph in requested format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS_DIR="$AGENT_ROOT/runs"

if [[ $# -lt 1 ]]; then
  echo "Usage: dependency-graph.sh <ticket_id> [--json|--ascii|--dot]" >&2
  exit 1
fi

ticket_id="$1"
shift
format="json"

for arg in "$@"; do
  case "$arg" in
    --json)  format="json" ;;
    --ascii) format="ascii" ;;
    --dot)   format="dot" ;;
    *)
      echo "Unknown flag: $arg" >&2
      echo "Usage: dependency-graph.sh <ticket_id> [--json|--ascii|--dot]" >&2
      exit 1
      ;;
  esac
done

# Look for local ticket data first
ticket_file="$RUNS_DIR/$ticket_id/ticket.json"
prd_file="$RUNS_DIR/$ticket_id/PRD.json"

python3 -c "
import json, sys, os

ticket_id = sys.argv[1]
fmt = sys.argv[2]
ticket_file = sys.argv[3]
prd_file = sys.argv[4]

nodes = []
edges = []
seen = set()

def add_node(nid, status='unknown'):
    if nid not in seen:
        seen.add(nid)
        nodes.append({'id': nid, 'status': status})

# Try ticket.json for linked_issues
if os.path.isfile(ticket_file):
    with open(ticket_file) as f:
        data = json.load(f)
    add_node(ticket_id, data.get('status', 'in_progress'))
    for li in data.get('linked_issues', []):
        link_id = li.get('ticket_id', li.get('id', ''))
        link_type = li.get('type', 'related')
        link_status = li.get('status', 'unknown')
        if link_id:
            add_node(link_id, link_status)
            edges.append({'from': link_id, 'to': ticket_id, 'type': link_type})

# Try PRD.json for dependency info
elif os.path.isfile(prd_file):
    with open(prd_file) as f:
        prd = json.load(f)
    add_node(ticket_id, prd.get('overall_status', 'unknown'))
    base = prd.get('base_branch', 'main')
    dep_ticket = prd.get('dependency_ticket', '')
    if dep_ticket:
        add_node(dep_ticket, 'dependency')
        edges.append({'from': dep_ticket, 'to': ticket_id, 'type': 'blocked_by'})
else:
    # No local data — output empty graph
    add_node(ticket_id, 'unknown')

if fmt == 'json':
    result = {'nodes': nodes, 'edges': edges}
    json.dump(result, sys.stdout, indent=2)
    print()

elif fmt == 'ascii':
    if not edges:
        print(f'{ticket_id} (no dependencies)')
    else:
        for edge in edges:
            arrow = '-->' if edge['type'] == 'blocked_by' else '---'
            print(f\"  {edge['from']} {arrow} {edge['to']}  [{edge['type']}]\")
    print()
    for node in nodes:
        print(f\"  {node['id']}: {node['status']}\")

elif fmt == 'dot':
    print('digraph dependencies {')
    print('  rankdir=LR;')
    for node in nodes:
        label = f\"{node['id']}\\n({node['status']})\"
        print(f'  \"{node[\"id\"]}\" [label=\"{label}\"];')
    for edge in edges:
        style = 'bold' if edge['type'] == 'blocked_by' else 'dashed'
        print(f'  \"{edge[\"from\"]}\" -> \"{edge[\"to\"]}\" [label=\"{edge[\"type\"]}\", style={style}];')
    print('}')
" "$ticket_id" "$format" "$ticket_file" "$prd_file"
