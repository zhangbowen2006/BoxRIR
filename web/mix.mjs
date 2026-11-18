const byId = id => document.getElementById(id);
const scene = byId('scene');
const status = byId('status');
const trackFiles = byId('track-files');
const results = byId('results');
const downloads = byId('downloads');
const player = byId('wet-player');
const run = byId('run');
const cancel = byId('cancel');
const maxWavBytes = 4 * 1024 * 1024;
const frequencies = [330, 554, 440, 698];
const preset = {
  version: 1,
  scene: {
    room: [6, 4, 3],
    receivers: [[2.6, 1.3, 1.4], [3.4, 2.15, 1.35]],
    absorption: [0.36, 0.48, 0.43, 0.3, 0.55, 0.4],
    sample_rate: 16000,
    max_order: 2,
    duration_ms: 250,
  },
  tracks: [
    {id: 'foreground', source: [1.25, 1.6, 1.2], start_frame: 0, gain: 4.5},
    {id: 'background', source: [4.6, 2.5, 1.45], start_frame: 4000, gain: 3},
  ],
};

const chosenFiles = new Map();
let active = null;
let resultUrls = [];

function showStatus(message, failed = false) {
  status.textContent = message;
  status.classList.toggle('error', failed);
}

function setBusy(busy) {
  run.disabled = busy;
  cancel.disabled = !busy;
}

function stop() {
  const job = active;
  active = null;
  job?.worker?.terminate();
  setBusy(false);
}

function clearResults() {
  results.hidden = true;
  byId('empty').hidden = false;
  player.pause();
  player.removeAttribute('src');
  player.load();
  downloads.replaceChildren();
  byId('track-report').replaceChildren();
  for (const url of resultUrls) URL.revokeObjectURL(url);
  resultUrls = [];
}

function invalidate(message) {
  stop();
  clearResults();
  showStatus(message);
}

function readSpec(text) {
  if (text.length > 65536) throw Error('录音参数不能超过 65536 字符。');
  const value = JSON.parse(text);
  const {tracks, scene: room} = value ?? {};
  if (!Array.isArray(tracks) || tracks.length < 1 || tracks.length > 4) {
    throw Error('tracks 必须包含 1 至 4 条轨道。');
  }
  const ids = tracks.map(track => track?.id);
  if (ids.some(id => typeof id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(id)) ||
      new Set(ids).size !== ids.length) {
    throw Error('每条轨道需要不同的 ID，使用字母、数字、连字符或下划线，以字母或数字开头。');
  }
  const rate = room?.sample_rate;
  if (!Number.isInteger(rate) || rate < 8000 || rate > 96000) {
    throw Error('场景 sample_rate 必须是 8000–96000 之间的整数。');
  }
  return {ids, rate};
}

function showFileInputs(ids) {
  for (const id of chosenFiles.keys()) if (!ids.includes(id)) chosenFiles.delete(id);
  const inputs = ids.map((id, index) => {
    const item = document.createElement('div');
    item.className = 'track';
    const label = document.createElement('label');
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.wav,audio/wav,audio/x-wav';
    input.id = `dry-${id}`;
    label.htmlFor = input.id;
    label.textContent = `轨道 ${index + 1} · ${id}`;
    const description = document.createElement('div');
    description.className = 'track-description row';
    const display = document.createElement('p');
    display.className = 'note';
    const reset = document.createElement('button');
    reset.type = 'button';
    reset.className = 'secondary';
    reset.textContent = '改用合成音';
    function updateDescription() {
      const file = chosenFiles.get(id);
      display.textContent = file ? `已选 ${file.name}` : `默认 ${frequencies[index]} Hz 合成音`;
      reset.hidden = !file;
    }
    input.addEventListener('change', () => {
      if (input.files[0]) chosenFiles.set(id, input.files[0]);
      else chosenFiles.delete(id);
      updateDescription();
      invalidate('声源已修改，请重新生成。');
    });
    reset.addEventListener('click', () => {
      input.value = '';
      chosenFiles.delete(id);
      updateDescription();
      invalidate('已恢复合成音，请重新生成。');
    });
    updateDescription();
    description.append(display, reset);
    item.append(label, input, description);
    return item;
  });
  trackFiles.replaceChildren(...inputs);
}

function refreshInputs() {
  try {
    const {ids} = readSpec(scene.value);
    showFileInputs(ids);
  } catch (error) {
    trackFiles.replaceChildren();
    showStatus(error instanceof SyntaxError ? '录音参数需要有效的 JSON。' : error.message, true);
  }
}

function objectUrl(value, type) {
  const url = URL.createObjectURL(new Blob([value], {type}));
  resultUrls.push(url);
  return url;
}

function displayResult(report, wav) {
  byId('rate').textContent = `${report.sample_rate} Hz`;
  byId('channels').textContent = report.channels;
  byId('frames').textContent = report.frames;
  for (const track of report.tracks) {
    const row = document.createElement('tr');
    for (const value of [track.id, track.start_frame, track.end_frame, track.latency_samples]) {
      const cell = document.createElement('td');
      cell.textContent = value;
      row.append(cell);
    }
    byId('track-report').append(row);
  }
  const wetUrl = objectUrl(wav, 'audio/wav');
  player.src = wetUrl;
  const reportUrl = objectUrl(JSON.stringify(report, null, 2) + '\n', 'application/json');
  for (const [name, url] of [['wet.wav', wetUrl], ['report.json', reportUrl]]) {
    const link = document.createElement('a');
    link.className = 'download';
    link.href = url;
    link.download = name;
    link.textContent = name;
    downloads.append(link);
  }
  results.hidden = false;
  byId('empty').hidden = true;
  showStatus('计算完成。');
}

function loadPreset() {
  chosenFiles.clear();
  scene.value = JSON.stringify(preset, null, 2);
  invalidate('双声源示例已就绪。');
  refreshInputs();
}

async function generate() {
  if (active) return;
  clearResults();
  const job = {worker: null};
  active = job;
  setBusy(true);
  try {
    const sceneText = scene.value;
    const {ids, rate} = readSpec(sceneText);
    const sources = ids.map(id => chosenFiles.get(id));
    let total = 0;
    for (const [i, file] of sources.entries()) {
      if (!file) continue;
      if (file.size === 0) throw Error(`轨道 ${ids[i]} 的 WAV 文件为空。`);
      if (file.size > maxWavBytes) throw Error(`轨道 ${ids[i]} 的 WAV 文件不能超过 4 MiB。`);
      total += file.size;
    }
    if (total > 2 * maxWavBytes) throw Error('所有轨道的 WAV 文件总计不能超过 8 MiB。');
    showStatus('正在读取声源…');
    const trackData = await Promise.all(sources.map(async (file, i) => ({
      bytes: file ? await file.arrayBuffer() : null,
      frequency: frequencies[i],
    })));
    if (active !== job) return;
    const worker = new Worker(new URL('./mix-worker.mjs', import.meta.url), {type: 'module'});
    job.worker = worker;
    worker.onmessage = ({data}) => {
      if (active !== job) return;
      stop();
      if (!data.ok) {
        showStatus(data.error, true);
        return;
      }
      displayResult(data.report, data.wetWav);
    };
    worker.onerror = event => {
      if (active !== job) return;
      stop();
      showStatus(event.message || '无法运行录音计算。', true);
    };
    showStatus('正在计算房间传播和多轨混音…');
    worker.postMessage(
      {scene: sceneText, sampleRate: rate, tracks: trackData},
      trackData.flatMap(track => track.bytes === null ? [] : [track.bytes]),
    );
  } catch (error) {
    if (active !== job) return;
    stop();
    showStatus(error instanceof SyntaxError ? '录音参数需要有效的 JSON。' : error.message, true);
  }
}

byId('preset').addEventListener('click', loadPreset);
scene.addEventListener('input', () => {
  invalidate('录音参数已修改，请重新生成。');
  refreshInputs();
});
run.addEventListener('click', generate);
cancel.addEventListener('click', () => invalidate('已取消。'));
window.addEventListener('pagehide', () => {
  stop();
  clearResults();
});
loadPreset();
