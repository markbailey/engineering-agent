(function () {
  'use strict';

  // --- State ---
  const state = {
    runs: new Map(),
    activeRunId: null,
    viewFilter: 'active',
  };

  let autoScroll = true;
  const emptyStateTpl = document.getElementById('emptyState').cloneNode(true);

  // --- SSE ---
  let evtSource = null;

  function connect() {
    if (evtSource) { try { evtSource.close(); } catch {} }

    evtSource = new EventSource('/events');

    evtSource.onopen = () => {
      setConnected(true);
    };

    evtSource.onmessage = (e) => {
      try {
        const event = JSON.parse(e.data);
        handleEvent(event);
      } catch {}
    };

    evtSource.onerror = () => {
      setConnected(false);
    };
  }

  function setConnected(yes) {
    const dot = document.getElementById('connectionDot');
    const label = document.getElementById('connectionLabel');
    if (yes) {
      dot.classList.remove('disconnected');
      label.textContent = 'connected';
    } else {
      dot.classList.add('disconnected');
      label.textContent = 'reconnecting';
    }
  }

  // --- Initial load ---
  async function loadInitial() {
    try {
      const res = await fetch('/api/runs');
      const runs = await res.json();
      for (const run of runs) {
        state.runs.set(run.ticketId, run);
      }
      if (runs.length > 0 && !state.activeRunId) {
        const firstActive = runs.find(r => r.isActive === 'active');
        if (firstActive) {
          state.activeRunId = firstActive.ticketId;
        } else {
          state.viewFilter = 'inactive';
          state.activeRunId = runs[0].ticketId;
        }
      }
      render();
    } catch {}
  }

  // --- Event handling ---
  function handleEvent(event) {
    if (event.type === 'snapshot' && event.data) {
      state.runs.set(event.ticketId, event.data);
      if (!state.activeRunId && event.data.isActive === state.viewFilter) {
        state.activeRunId = event.ticketId;
      }
    } else if (event.type === 'remove') {
      state.runs.delete(event.ticketId);
      if (state.activeRunId === event.ticketId) {
        state.activeRunId = null;
      }
    }
    render();
  }

  // --- Rendering ---
  function render() {
    // Ensure activeRunId matches viewFilter — never override viewFilter
    if (state.runs.size > 0) {
      const currentRun = state.runs.get(state.activeRunId);
      if (!currentRun || currentRun.isActive !== state.viewFilter) {
        state.activeRunId = null;
        for (const [id, run] of state.runs) {
          if (run.isActive === state.viewFilter) {
            state.activeRunId = id;
            break;
          }
        }
      }
    }
    renderViewToggle();
    renderTabs();
    renderMain();
  }

  function renderViewToggle() {
    const container = document.getElementById('viewToggleContainer');
    container.innerHTML = '';

    if (state.runs.size === 0) return;

    let activeCount = 0;
    let inactiveCount = 0;
    for (const [, run] of state.runs) {
      if (run.isActive === 'active') activeCount++;
      else inactiveCount++;
    }

    const toggle = document.createElement('div');
    toggle.className = 'view-toggle';

    const activeBtn = document.createElement('button');
    activeBtn.className = 'view-toggle-btn' + (state.viewFilter === 'active' ? ' selected' : '');
    activeBtn.innerHTML = 'Active<span class="view-toggle-count">' + activeCount + '</span>';
    activeBtn.onclick = () => { state.viewFilter = 'active'; render(); };

    const inactiveBtn = document.createElement('button');
    inactiveBtn.className = 'view-toggle-btn' + (state.viewFilter === 'inactive' ? ' selected' : '');
    inactiveBtn.innerHTML = 'Inactive<span class="view-toggle-count">' + inactiveCount + '</span>';
    inactiveBtn.onclick = () => { state.viewFilter = 'inactive'; render(); };

    toggle.appendChild(activeBtn);
    toggle.appendChild(inactiveBtn);
    container.appendChild(toggle);
  }

  function renderTabs() {
    const bar = document.getElementById('tabBar');
    bar.innerHTML = '';

    // Filtered tabs
    for (const [id, run] of state.runs) {
      if (run.isActive !== state.viewFilter) continue;

      const tab = document.createElement('button');
      tab.className = 'tab' + (id === state.activeRunId ? ' active' : '');
      tab.onclick = () => { state.activeRunId = id; state.viewFilter = run.isActive; render(); };

      const dot = document.createElement('span');
      dot.className = 'tab-status ' + (run.overallStatus || 'pending');
      tab.appendChild(dot);

      const label = document.createElement('span');
      label.textContent = id;
      tab.appendChild(label);

      bar.appendChild(tab);
    }
  }

  function renderMain() {
    const main = document.getElementById('mainContent');
    const empty = document.getElementById('emptyState');
    const banner = document.getElementById('errorBanner');

    const run = state.activeRunId ? state.runs.get(state.activeRunId) : null;
    if (!run) {
      main.innerHTML = '';
      const placeholder = emptyStateTpl.cloneNode(true);
      placeholder.removeAttribute('id');
      if (state.runs.size > 0) {
        placeholder.querySelector('div:nth-child(2)').textContent = 'no ' + state.viewFilter + ' runs';
        placeholder.querySelector('div:nth-child(3)').textContent = '';
      }
      main.appendChild(placeholder);
      banner.classList.remove('visible');
      return;
    }

    // Error banner
    if (run.errors.length > 0) {
      const lastErr = run.errors[run.errors.length - 1];
      document.getElementById('errorBannerText').textContent = lastErr.msg;
      banner.classList.add('visible');
    } else {
      banner.classList.remove('visible');
    }

    main.innerHTML = '';

    // Sidebar
    const sidebar = document.createElement('div');
    sidebar.className = 'sidebar';

    // Workflow section
    const wfSection = document.createElement('div');
    wfSection.className = 'sidebar-section';
    const wfTitle = document.createElement('div');
    wfTitle.className = 'sidebar-title';
    wfTitle.textContent = 'Workflow';
    wfSection.appendChild(wfTitle);

    const steps = document.createElement('div');
    steps.className = 'workflow-steps';
    for (const stage of run.stages) {
      const step = document.createElement('div');
      step.className = 'step ' + stage.status;

      const icon = document.createElement('div');
      icon.className = 'step-icon';
      if (stage.status === 'complete') icon.textContent = '\u2713';
      else if (stage.status === 'in_progress') icon.textContent = '\u25B8';
      else if (stage.status === 'error') icon.textContent = '!';
      else icon.textContent = '\u00B7';

      const label = document.createElement('span');
      label.textContent = stage.label;

      step.appendChild(icon);
      step.appendChild(label);
      steps.appendChild(step);
    }
    wfSection.appendChild(steps);
    sidebar.appendChild(wfSection);

    // Status footer
    const statusBar = document.createElement('div');
    statusBar.className = 'status-bar';

    const statusLabel = document.createElement('div');
    statusLabel.className = 'status-label';
    statusLabel.textContent = 'Status';
    statusBar.appendChild(statusLabel);

    const statusVal = document.createElement('div');
    statusVal.className = 'status-value ' + (run.overallStatus || '');
    statusVal.textContent = run.overallStatus || 'unknown';
    statusBar.appendChild(statusVal);

    const counters = document.createElement('div');
    counters.className = 'status-counters';
    counters.innerHTML = '<span>Reviews: ' + run.reviewRounds + '</span><span>Feedback: ' + run.feedbackRounds + '</span>';
    statusBar.appendChild(counters);

    sidebar.appendChild(statusBar);
    main.appendChild(sidebar);

    // Details panel
    const details = document.createElement('div');
    details.className = 'details';

    // Active agent
    const agentSection = document.createElement('div');
    agentSection.className = 'detail-section';
    const agentTitle = document.createElement('div');
    agentTitle.className = 'detail-title';
    agentTitle.textContent = 'Active Agent';
    agentSection.appendChild(agentTitle);

    if (run.activeAgent) {
      const agentDisplay = document.createElement('div');
      agentDisplay.className = 'agent-display';
      const pulse = document.createElement('div');
      pulse.className = 'agent-pulse';
      const name = document.createElement('span');
      name.className = 'agent-name';
      name.textContent = run.activeAgent;
      agentDisplay.appendChild(pulse);
      agentDisplay.appendChild(name);
      agentSection.appendChild(agentDisplay);
    } else {
      const idle = document.createElement('div');
      idle.className = 'agent-idle';
      idle.textContent = 'idle';
      agentSection.appendChild(idle);
    }
    details.appendChild(agentSection);

    // Task queue
    const taskSection = document.createElement('div');
    taskSection.className = 'detail-section';
    const taskTitle = document.createElement('div');
    taskTitle.className = 'detail-title';
    taskTitle.textContent = 'Task Queue';
    taskSection.appendChild(taskTitle);

    if (run.tasks.length > 0) {
      const taskList = document.createElement('div');
      taskList.className = 'task-list';
      for (const task of run.tasks) {
        const item = document.createElement('div');
        item.className = 'task-item';

        const badge = document.createElement('span');
        badge.className = 'task-badge ' + task.status;
        badge.textContent = task.status;

        const desc = document.createElement('span');
        desc.className = 'task-desc';
        desc.textContent = task.description;

        item.appendChild(badge);
        item.appendChild(desc);

        if (task.repo) {
          const repo = document.createElement('span');
          repo.className = 'task-repo';
          repo.textContent = task.repo;
          item.appendChild(repo);
        }

        taskList.appendChild(item);
      }
      taskSection.appendChild(taskList);
    } else {
      const noData = document.createElement('div');
      noData.className = 'no-data';
      noData.textContent = 'no tasks loaded';
      taskSection.appendChild(noData);
    }
    details.appendChild(taskSection);

    // Log stream
    const logWrapper = document.createElement('div');
    logWrapper.className = 'log-stream-wrapper';

    const logHeader = document.createElement('div');
    logHeader.className = 'log-stream-header';
    const logTitle = document.createElement('div');
    logTitle.className = 'detail-title';
    logTitle.style.marginBottom = '0';
    logTitle.textContent = 'Log Stream';
    logHeader.appendChild(logTitle);

    const scrollBtn = document.createElement('button');
    scrollBtn.className = 'log-autoscroll' + (autoScroll ? '' : ' paused');
    scrollBtn.textContent = autoScroll ? '\u25BC auto-scroll' : '\u25A0 paused';
    scrollBtn.onclick = () => {
      autoScroll = !autoScroll;
      render();
    };
    logHeader.appendChild(scrollBtn);
    logWrapper.appendChild(logHeader);

    const logStream = document.createElement('div');
    logStream.className = 'log-stream';
    logStream.id = 'logStream';

    for (const entry of run.recentLogs) {
      logStream.appendChild(createLogEntry(entry));
    }
    logWrapper.appendChild(logStream);

    // Pause auto-scroll on user scroll up
    logStream.addEventListener('scroll', () => {
      const atBottom = logStream.scrollHeight - logStream.scrollTop - logStream.clientHeight < 30;
      if (!atBottom && autoScroll) {
        autoScroll = false;
        scrollBtn.className = 'log-autoscroll paused';
        scrollBtn.textContent = '\u25A0 paused';
      }
    });

    details.appendChild(logWrapper);
    main.appendChild(details);

    // Auto-scroll
    if (autoScroll) {
      requestAnimationFrame(() => {
        logStream.scrollTop = logStream.scrollHeight;
      });
    }
  }

  function createLogEntry(entry) {
    const el = document.createElement('div');
    el.className = 'log-entry';

    const ts = document.createElement('span');
    ts.className = 'log-ts';
    ts.textContent = formatTime(entry.ts);

    const level = document.createElement('span');
    level.className = 'log-level ' + entry.level;
    level.textContent = entry.level;

    const cat = document.createElement('span');
    cat.className = 'log-cat';
    cat.textContent = '[' + entry.cat + ']';

    const msg = document.createElement('span');
    msg.className = 'log-msg';
    msg.textContent = entry.msg;

    el.appendChild(ts);
    el.appendChild(level);
    el.appendChild(cat);
    el.appendChild(msg);
    return el;
  }

  function formatTime(ts) {
    if (!ts) return '';
    try {
      const d = new Date(ts);
      if (isNaN(d.getTime())) return ts.substring(0, 8);
      return d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch {
      return ts;
    }
  }

  // --- Init ---
  loadInitial().then(() => connect());
})();
