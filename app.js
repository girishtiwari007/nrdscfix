'use strict';
const $ = selector => document.querySelector(selector);
const all = selector => [...document.querySelectorAll(selector)];
let toastTimer;
function toast(message) { $('#toast').textContent = message; $('#toast').classList.add('visible'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 6000); }
const downloadsMenu = $('.nav-downloads');
document.addEventListener('click', event => { if (!downloadsMenu.contains(event.target)) downloadsMenu.open = false; });
document.addEventListener('keydown', event => { if (event.key === 'Escape' && downloadsMenu.open) { downloadsMenu.open = false; downloadsMenu.querySelector('summary').focus(); } });
all('.nav-download-menu a').forEach(link => link.addEventListener('click', () => { downloadsMenu.open = false; }));
all('[data-launcher]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    try {
        if (!window.DSS_LAUNCHER) throw new Error('Launcher content unavailable');
        const blob = new Blob([window.DSS_LAUNCHER], {type:'application/octet-stream'});
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url; link.download = 'Start-DSS-Online.cmd';
        document.body.appendChild(link); link.click(); link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 60000);
        toast('Save Start-DSS-Online.cmd, open it from Downloads, then approve UAC. If your browser blocks the download, use the standby PowerShell command.');
    } catch {
        toast('This browser could not prepare the launcher. Use the standby PowerShell command shown on this page.');
        $('#standby-command').scrollIntoView({behavior:'smooth', block:'center'});
    }
}));
$('#copy-command').addEventListener('click', async () => {
    try {
        await navigator.clipboard.writeText($('#standby-command').textContent.trim());
        toast('Command copied. Paste both lines into Windows PowerShell opened as administrator.');
    } catch {
        const range = document.createRange(); range.selectNodeContents($('#standby-command'));
        const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
        toast('Command selected. Copy manually, then paste into Windows PowerShell opened as administrator.');
    }
});
$('#live-link').addEventListener('click', () => toast('isLive opened in another tab. Check its response for success and version 4.1.8.'));
$('#platform').textContent = /Windows/i.test(navigator.userAgent) ? 'Windows detected' : 'Launcher requires Windows';
