(function () {
  'use strict';

  // --- State ---
  const state = {
    runs: new Map(),
    activeRunId: null,
    logFilters: { INFO: true, WARN: true, ERROR: true, EVENT: true },
  };

  let autoScroll = true;
  let notificationPermission = 'default';
  let lastSeenLogCount = new Map();

  document.addEventListener('click', () => {
    if (notificationPermission === 'default' && 'Notification' in window) {
      Notification.requestPermission().then(p => { notificationPermission = p; });
    }
  }, { once: true });

  function notify(title, body) {
    if (notificationPermission === 'granted' && document.hidden) {
      try { new Notification(title, { body, icon: '' }); } catch {}
    }
  }

  let initialLoaded = false;
  let lastRenderedRunId = null;
  let lastRenderedState = null;
  const emptyStateTpl = document.getElementById('emptyState').cloneNode(true);

  // --- SSE ---
  let evtSource = null;

  function connect() {
    if (evtSource) { try { evtSource.close(); } catch (err) { console.warn('EventSource close error:', err); } }

    evtSource = new EventSource('/events');

    evtSource.onopen = () => {
      setConnected(true);
    };

    evtSource.onmessage = (e) => {
      try {
        const event = JSON.parse(e.data);
        handleEvent(event);
      } catch (err) { console.warn('SSE parse error:', err); }
    };

    evtSource.onerror = (err) => {
      console.warn('EventSource error:', err);
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
        const firstActive = runs.find(r => r.isActive);
        if (firstActive) state.activeRunId = firstActive.ticketId;
      }
      initialLoaded = true;
      render();
    } catch (err) { console.warn('Initial load failed:', err); }
  }

  // --- Event handling ---
  function handleEvent(event) {
    if (event.type === 'snapshot' && event.data) {
      // Check for new ERROR logs
      const prevCount = lastSeenLogCount.get(event.ticketId) || 0;
      const newLogs = (event.data.recentLogs || []);
      if (newLogs.length > prevCount) {
        const newEntries = newLogs.slice(prevCount);
        for (const entry of newEntries) {
          if (entry.level === 'ERROR') {
            notify(event.ticketId + ': Error', entry.msg);
          }
        }
      }
      lastSeenLogCount.set(event.ticketId, newLogs.length);

      // Check for status transitions
      const prevRun = state.runs.get(event.ticketId);
      if (prevRun && prevRun.overallStatus !== event.data.overallStatus) {
        if (event.data.overallStatus === 'done') {
          notify(event.ticketId + ': Complete', 'Run finished successfully');
        } else if (event.data.overallStatus === 'escalated') {
          notify(event.ticketId + ': Escalated', 'Run needs human attention');
        }
      }

      state.runs.set(event.ticketId, event.data);
      if (!state.activeRunId && event.data.isActive) {
        state.activeRunId = event.ticketId;
      }
    } else if (event.type === 'remove') {
      state.runs.delete(event.ticketId);
      if (state.activeRunId === event.ticketId) {
        state.activeRunId = null;
      }
    }
    if (initialLoaded) render();
  }

  // --- Rendering ---
  function render() {
    // If activeRunId is gone or inactive, pick first active run
    const currentRun = state.runs.get(state.activeRunId);
    if (!currentRun || !currentRun.isActive) {
      state.activeRunId = null;
      for (const [id, run] of state.runs) {
        if (run.isActive) { state.activeRunId = id; break; }
      }
    }
    renderTabs();

    const tabSwitched = state.activeRunId !== lastRenderedRunId;
    lastRenderedRunId = state.activeRunId;

    if (tabSwitched || !lastRenderedState) {
      renderMain();
    } else {
      renderMainDiff();
    }

    // Snapshot current state for next comparison
    const run = state.activeRunId ? state.runs.get(state.activeRunId) : null;
    if (run) {
      lastRenderedState = {
        overallStatus: run.overallStatus,
        stages: run.stages.map(s => s.id + ':' + s.status),
        taskHash: JSON.stringify(run.tasks),
        logCount: run.recentLogs.length,
        activeAgent: run.activeAgent,
        reviewRounds: run.reviewRounds,
        feedbackRounds: run.feedbackRounds,
        errors: run.errors.length,
      };
    } else {
      lastRenderedState = null;
    }
  }

  function renderMainDiff() {
    const run = state.activeRunId ? state.runs.get(state.activeRunId) : null;
    if (!run || !lastRenderedState) { renderMain(); return; }

    // Update workflow step statuses
    const steps = document.querySelectorAll('.step');
    if (steps.length === run.stages.length) {
      for (let i = 0; i < run.stages.length; i++) {
        const newKey = run.stages[i].id + ':' + run.stages[i].status;
        if (lastRenderedState.stages[i] !== newKey) {
          steps[i].className = 'step ' + run.stages[i].status;
          const icon = steps[i].querySelector('.step-icon');
          if (icon) {
            if (run.stages[i].status === 'complete') icon.textContent = '\u2713';
            else if (run.stages[i].status === 'in_progress') icon.textContent = '\u25B8';
            else if (run.stages[i].status === 'error') icon.textContent = '!';
            else icon.textContent = '\u00B7';
          }
        }
      }
    }

    // Update sidebar status
    const statusVal = document.querySelector('.status-value');
    if (statusVal && run.overallStatus !== lastRenderedState.overallStatus) {
      statusVal.className = 'status-value ' + (run.overallStatus || '');
      statusVal.textContent = run.overallStatus || 'unknown';
    }

    // Update counters
    if (run.reviewRounds !== lastRenderedState.reviewRounds || run.feedbackRounds !== lastRenderedState.feedbackRounds) {
      const counters = document.querySelector('.status-counters');
      if (counters) counters.innerHTML = '<span>Reviews: ' + run.reviewRounds + '</span><span>Feedback: ' + run.feedbackRounds + '</span>';
    }

    // Update active agent
    if (run.activeAgent !== lastRenderedState.activeAgent) {
      const agentSection = document.querySelector('.detail-section');
      if (agentSection) {
        const existing = agentSection.querySelector('.agent-display, .agent-idle');
        if (existing) existing.remove();
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
      }
    }

    // Task list changed — full re-render
    if (JSON.stringify(run.tasks) !== lastRenderedState.taskHash) { renderMain(); return; }

    // Update error banner
    const banner = document.getElementById('errorBanner');
    if (run.errors.length > 0 && run.errors.length !== lastRenderedState.errors) {
      document.getElementById('errorBannerText').textContent = run.errors[run.errors.length - 1].msg;
      banner.classList.add('visible');
    } else if (run.errors.length === 0 && lastRenderedState.errors > 0) {
      banner.classList.remove('visible');
    }

    // Incremental log stream update
    const logStream = document.getElementById('logStream');
    if (logStream && run.recentLogs.length !== lastRenderedState.logCount) {
      const filteredLogs = run.recentLogs.filter(e => state.logFilters[e.level]);
      const currentEntries = logStream.querySelectorAll('.log-entry');
      const currentCount = currentEntries.length;
      const newCount = filteredLogs.length;
      if (newCount > currentCount) {
        const newEntries = filteredLogs.slice(currentCount);
        for (const entry of newEntries) logStream.appendChild(createLogEntry(entry));
      } else if (newCount < currentCount) {
        const toRemove = currentCount - newCount;
        for (let i = 0; i < toRemove && logStream.firstChild; i++) logStream.removeChild(logStream.firstChild);
      }
      if (autoScroll) requestAnimationFrame(() => { logStream.scrollTop = logStream.scrollHeight; });
    }
  }

  function renderTabs() {
    const bar = document.getElementById('tabBar');
    bar.innerHTML = '';

    for (const [id, run] of state.runs) {
      if (!run.isActive) continue;

      const tab = document.createElement('button');
      tab.className = 'tab' + (id === state.activeRunId ? ' active' : '');
      tab.onclick = () => { state.activeRunId = id; render(); };

      const dot = document.createElement('span');
      dot.className = 'tab-status ' + (run.overallStatus || 'pending');
      tab.appendChild(dot);

      const label = document.createElement('span');
      label.textContent = id;
      tab.appendChild(label);

      bar.appendChild(tab);
    }
  }

  function renderReviewPanel(container, review) {
    const items = review.issues || review.entries || (Array.isArray(review) ? review : []);
    if (items.length === 0) { container.textContent = 'No issues'; return; }
    const table = document.createElement('table');
    table.className = 'artifact-table';
    table.innerHTML = '<thead><tr><th>Sev</th><th>File</th><th>Line</th><th>Issue</th><th>Status</th></tr></thead>';
    const tbody = document.createElement('tbody');
    for (const item of items) {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td><span class="sev-badge ' + (item.severity || 'low') + '">' + (item.severity || '?') + '</span></td>'
        + '<td>' + (item.file || '-') + '</td>'
        + '<td>' + (item.line || '-') + '</td>'
        + '<td>' + (item.message || item.comment || '-') + '</td>'
        + '<td>' + (item.status || '-') + '</td>';
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    container.appendChild(table);
  }

  function renderEscalationPanel(container, escalation) {
    const items = escalation.entries || (Array.isArray(escalation) ? escalation : []);
    if (items.length === 0) { container.textContent = 'No escalations'; return; }
    for (const item of items) {
      const entry = document.createElement('div');
      entry.className = 'escalation-entry';
      entry.innerHTML = '<span class="sev-badge ' + (item.severity || 'medium') + '">' + (item.severity || '?') + '</span> '
        + '<strong>' + (item.category || '?') + '</strong>: ' + (item.summary || item.message || '-');
      container.appendChild(entry);
    }
  }

  function renderFeedbackPanel(container, feedback) {
    const items = feedback.items || feedback.entries || (Array.isArray(feedback) ? feedback : []);
    if (items.length === 0) { container.textContent = 'No feedback'; return; }
    for (const item of items) {
      const entry = document.createElement('div');
      entry.className = 'feedback-entry';
      entry.innerHTML = '<span class="sev-badge info">' + (item.type || 'comment') + '</span> '
        + (item.file ? '<code>' + item.file + '</code>: ' : '')
        + (item.comment || item.body || '-')
        + (item.status ? ' <span class="feedback-status">[' + item.status + ']</span>' : '');
      container.appendChild(entry);
    }
  }

  function renderMain() {
    const oldElapsed = document.getElementById('elapsedTime');
    if (oldElapsed && oldElapsed.dataset.timer) {
      clearInterval(Number(oldElapsed.dataset.timer));
    }

    const main = document.getElementById('mainContent');
    const empty = document.getElementById('emptyState');
    const banner = document.getElementById('errorBanner');

    const run = state.activeRunId ? state.runs.get(state.activeRunId) : null;
    if (!run) {
      main.innerHTML = '';
      const placeholder = emptyStateTpl.cloneNode(true);
      placeholder.removeAttribute('id');
      if (state.runs.size > 0) {
        placeholder.querySelector('div:nth-child(2)').textContent = 'no runs';
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

    if (run.startedAt) {
      const elapsed = document.createElement('div');
      elapsed.className = 'status-elapsed';
      elapsed.id = 'elapsedTime';
      const updateElapsed = () => {
        const start = new Date(run.startedAt).getTime();
        const end = run.isActive ? Date.now() : (run.lastActivity ? new Date(run.lastActivity).getTime() : Date.now());
        const diffMs = end - start;
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        elapsed.textContent = mins + 'm ' + secs + 's';
      };
      updateElapsed();
      if (run.isActive) {
        const timer = setInterval(updateElapsed, 1000);
        elapsed.dataset.timer = timer;
      }
      statusBar.appendChild(elapsed);
    }

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
      const verified = run.tasks.filter(t => t.status === 'verified' || t.status === 'complete').length;
      const total = run.tasks.length;

      const progressWrapper = document.createElement('div');
      progressWrapper.className = 'task-progress';

      const progressLabel = document.createElement('span');
      progressLabel.className = 'task-progress-label';
      progressLabel.textContent = verified + '/' + total + ' verified';
      progressWrapper.appendChild(progressLabel);

      const progressBar = document.createElement('div');
      progressBar.className = 'progress-bar';
      const progressFill = document.createElement('div');
      progressFill.className = 'progress-fill';
      progressFill.style.width = (total > 0 ? (verified / total * 100) : 0) + '%';
      progressBar.appendChild(progressFill);
      progressWrapper.appendChild(progressBar);

      taskSection.appendChild(progressWrapper);

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

    // Artifact panels
    const artifactConfigs = [
      { key: 'reviewContent', title: 'Review Issues', renderFn: renderReviewPanel },
      { key: 'escalationContent', title: 'Escalations', renderFn: renderEscalationPanel },
      { key: 'feedbackContent', title: 'PR Feedback', renderFn: renderFeedbackPanel },
    ];

    for (const cfg of artifactConfigs) {
      const content = run[cfg.key];
      if (!content) continue;

      const panel = document.createElement('div');
      panel.className = 'artifact-panel';

      const header = document.createElement('button');
      header.className = 'artifact-toggle';
      header.textContent = '\u25B8 ' + cfg.title;
      header.onclick = () => {
        const body = panel.querySelector('.artifact-content');
        if (body.style.display === 'none') {
          body.style.display = '';
          header.textContent = '\u25BE ' + cfg.title;
        } else {
          body.style.display = 'none';
          header.textContent = '\u25B8 ' + cfg.title;
        }
      };
      panel.appendChild(header);

      const body = document.createElement('div');
      body.className = 'artifact-content';
      body.style.display = 'none';
      cfg.renderFn(body, content);
      panel.appendChild(body);

      details.appendChild(panel);
    }

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

    const filterBar = document.createElement('div');
    filterBar.className = 'log-filter-bar';
    for (const level of ['INFO', 'WARN', 'ERROR', 'EVENT']) {
      const btn = document.createElement('button');
      btn.className = 'log-filter-btn ' + level + (state.logFilters[level] ? ' active' : '');
      btn.textContent = level;
      btn.onclick = () => { state.logFilters[level] = !state.logFilters[level]; render(); };
      filterBar.appendChild(btn);
    }
    logHeader.appendChild(filterBar);

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

    const filteredLogs = run.recentLogs.filter(e => state.logFilters[e.level]);
    for (const entry of filteredLogs) {
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

    if (entry.details && Object.keys(entry.details).length > 0) {
      const toggle = document.createElement('button');
      toggle.className = 'log-details-toggle';
      toggle.textContent = '\u25B8';
      toggle.onclick = () => {
        const existing = el.querySelector('.log-details-content');
        if (existing) {
          existing.remove();
          toggle.textContent = '\u25B8';
        } else {
          const pre = document.createElement('pre');
          pre.className = 'log-details-content';
          pre.textContent = JSON.stringify(entry.details, null, 2);
          el.appendChild(pre);
          toggle.textContent = '\u25BE';
        }
      };
      el.appendChild(toggle);
    }

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
  connect();
  loadInitial();
})();
