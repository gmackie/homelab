const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

let currentTab = "video";
let currentPage = 1;
let searchQuery = "";
let platformFilter = "";

function formatDuration(seconds) {
  if (!seconds) return "";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function formatDate(dateStr) {
  if (!dateStr) return "";
  try {
    const d = new Date(dateStr);
    return d.toLocaleDateString();
  } catch {
    return dateStr;
  }
}

async function fetchCatalog() {
  const params = new URLSearchParams({
    tab: currentTab,
    page: currentPage,
  });
  if (searchQuery) params.set("q", searchQuery);
  if (platformFilter) params.set("platform", platformFilter);

  const content = $("#content");
  content.innerHTML = '<div class="loading">Loading...</div>';

  try {
    const resp = await fetch(`/catalog?${params}`);
    const data = await resp.json();
    render(data);
  } catch (e) {
    content.innerHTML = `<div class="empty">Failed to load: ${e.message}</div>`;
  }
}

function render(data) {
  const content = $("#content");
  if (data.items.length === 0) {
    content.innerHTML = `<div class="empty">No ${currentTab} items found</div>`;
    return;
  }

  switch (currentTab) {
    case "video":
      renderVideos(content, data.items);
      break;
    case "audio":
      renderMusic(content, data.items);
      break;
    case "image":
      renderImages(content, data.items);
      break;
  }
}

function renderVideos(container, items) {
  const grid = document.createElement("div");
  grid.className = "video-grid";

  for (const item of items) {
    const card = document.createElement("div");
    card.className = "video-card";
    card.innerHTML = `
      <div class="thumb">
        ${item.thumbnail_path ? `<img src="/thumb/${item.id}" alt="" loading="lazy">` : "&#9654;"}
        ${item.duration ? `<span class="duration">${formatDuration(item.duration)}</span>` : ""}
      </div>
      <div class="info">
        <div class="title">${esc(item.title)}</div>
        <div class="meta">
          <span>${esc(item.channel || "")} ${item.audio_path ? '<span class="audio-badge">&#9835;</span>' : ""}</span>
          <span class="platform-badge ${item.platform}">${esc(item.platform)}</span>
        </div>
      </div>
    `;
    card.addEventListener("click", () => openVideoPlayer(item, card));
    grid.appendChild(card);
  }

  container.innerHTML = "";
  container.appendChild(grid);
}

function openVideoPlayer(item, card) {
  const existing = $(".video-player");
  if (existing) existing.remove();

  const player = document.createElement("div");
  player.className = "video-player";
  player.innerHTML = `
    <video controls autoplay>
      <source src="/stream/${item.id}" type="video/mp4">
    </video>
    <div class="player-controls">
      <span class="player-title">${esc(item.title)}</span>
      <div class="player-actions">
        ${!item.audio_path ? `<button onclick="extractAudio('${item.id}', this)">Extract Audio</button>` : ""}
        <button onclick="this.closest('.video-player').remove()">Close</button>
      </div>
    </div>
  `;
  card.parentNode.insertBefore(player, card);
  player.querySelector("video").scrollIntoView({ behavior: "smooth", block: "center" });
}

window.extractAudio = async function (id, btn) {
  btn.textContent = "Extracting...";
  btn.disabled = true;
  try {
    const resp = await fetch(`/catalog/${id}/extract-audio`, { method: "POST" });
    const data = await resp.json();
    if (data.status === "ok" || data.status === "already_extracted") {
      btn.textContent = "Done!";
      setTimeout(() => fetchCatalog(), 1000);
    } else {
      btn.textContent = "Failed";
    }
  } catch {
    btn.textContent = "Error";
  }
};

function renderMusic(container, items) {
  const list = document.createElement("div");
  list.className = "music-list";

  for (const item of items) {
    const row = document.createElement("div");
    row.className = "music-row";
    row.dataset.id = item.id;
    row.innerHTML = `
      <button class="play-btn">&#9654;</button>
      <div class="track-info">
        <div class="track-title">${esc(item.title)}</div>
        <div class="track-artist">${esc(item.channel || item.platform)}</div>
      </div>
      <span class="platform-badge ${item.platform}">${esc(item.platform)}</span>
      <span class="track-duration">${formatDuration(item.duration)}</span>
    `;
    row.querySelector(".play-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      playTrack(item, row);
    });
    row.addEventListener("click", () => playTrack(item, row));
    list.appendChild(row);
  }

  container.innerHTML = "";
  container.appendChild(list);
}

function playTrack(item, row) {
  const audio = $("#global-audio");
  const nowPlaying = $("#now-playing");
  const title = $("#now-playing-title");

  const src = item.audio_path ? `/stream/${item.id}/audio` : `/stream/${item.id}`;
  audio.src = src;
  audio.play();

  title.textContent = `${item.title} - ${item.channel || item.platform}`;
  nowPlaying.classList.remove("hidden");

  $$(".music-row.playing").forEach((r) => r.classList.remove("playing"));
  row.classList.add("playing");
}

function renderImages(container, items) {
  const grid = document.createElement("div");
  grid.className = "image-grid";

  for (const item of items) {
    const card = document.createElement("div");
    card.className = "image-card";
    card.innerHTML = item.thumbnail_path
      ? `<img src="/thumb/${item.id}" alt="${esc(item.title)}" loading="lazy">`
      : `<img src="/stream/${item.id}" alt="${esc(item.title)}" loading="lazy">`;
    card.addEventListener("click", () => openImageOverlay(item));
    grid.appendChild(card);
  }

  container.innerHTML = "";
  container.appendChild(grid);
}

function openImageOverlay(item) {
  const overlay = document.createElement("div");
  overlay.className = "image-overlay";
  overlay.innerHTML = `<img src="/stream/${item.id}" alt="${esc(item.title)}">`;
  overlay.addEventListener("click", () => overlay.remove());
  document.body.appendChild(overlay);
}

function esc(str) {
  const div = document.createElement("div");
  div.textContent = str || "";
  return div.innerHTML;
}

// Tab switching
$$(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    $$(".tab").forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");
    currentTab = tab.dataset.tab;
    currentPage = 1;
    fetchCatalog();
  });
});

// Search
let searchTimeout;
$("#search").addEventListener("input", (e) => {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    searchQuery = e.target.value;
    currentPage = 1;
    fetchCatalog();
  }, 300);
});

// Platform filter
$("#platform-filter").addEventListener("change", (e) => {
  platformFilter = e.target.value;
  currentPage = 1;
  fetchCatalog();
});

// Sync button
$("#sync-btn").addEventListener("click", async () => {
  const btn = $("#sync-btn");
  btn.disabled = true;
  btn.textContent = "...";
  try {
    await fetch("/catalog/sync", { method: "POST" });
    fetchCatalog();
  } catch {
    // ignore
  }
  btn.disabled = false;
  btn.innerHTML = "&#8635;";
});

// Settings
$("#settings-btn").addEventListener("click", async () => {
  const dialog = $("#settings-dialog");
  const rulesDiv = $("#channel-rules");

  try {
    const resp = await fetch("/channels");
    const rules = await resp.json();
    if (rules.length === 0) {
      rulesDiv.innerHTML = '<div class="empty" style="padding:1rem">No channel rules configured</div>';
    } else {
      rulesDiv.innerHTML = rules
        .map(
          (r) => `
        <div class="channel-rule">
          <span class="channel-name">${esc(r.channel)} <span class="platform-badge ${r.platform}">${esc(r.platform)}</span></span>
          <select data-channel="${esc(r.channel)}" data-platform="${esc(r.platform)}">
            <option value="video" ${r.mode === "video" ? "selected" : ""}>Video</option>
            <option value="audio_only" ${r.mode === "audio_only" ? "selected" : ""}>Audio Only</option>
          </select>
        </div>
      `
        )
        .join("");

      rulesDiv.querySelectorAll("select").forEach((sel) => {
        sel.addEventListener("change", async () => {
          await fetch(`/channels/${encodeURIComponent(sel.dataset.channel)}`, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ platform: sel.dataset.platform, mode: sel.value }),
          });
        });
      });
    }
  } catch {
    rulesDiv.innerHTML = '<div class="empty" style="padding:1rem">Failed to load rules</div>';
  }

  dialog.showModal();
});

$("#close-settings").addEventListener("click", () => {
  $("#settings-dialog").close();
});

$("#manual-sync").addEventListener("click", async () => {
  const btn = $("#manual-sync");
  btn.disabled = true;
  btn.textContent = "Syncing...";
  try {
    const resp = await fetch("/catalog/sync", { method: "POST" });
    const data = await resp.json();
    btn.textContent = `Synced (${data.new_items} new)`;
  } catch {
    btn.textContent = "Failed";
  }
  setTimeout(() => {
    btn.disabled = false;
    btn.textContent = "Sync Now";
  }, 2000);
});

// Initial load
fetchCatalog();
