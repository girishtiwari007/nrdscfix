'use strict';
const $ = selector => document.querySelector(selector);
const all = selector => [...document.querySelectorAll(selector)];
let toastTimer;
function toast(message) { $('#toast').textContent = message; $('#toast').classList.add('visible'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 6000); }
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

function saveTextFile(name, text) {
    const blob = new Blob([text], {type:'text/plain;charset=utf-8'});
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a'); link.href = url; link.download = name;
    document.body.appendChild(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
}
$('#download-help').addEventListener('click', () => {
    saveTextFile('Digital-Service-help.txt', [
        'Digital Signing Service 4.1.8 Troubleshooter - Help',
        'Developed by Girish Tiwari', '',
        '1. Download and open the PowerShell Launcher, then approve Windows UAC.',
        '2. Alternatively run the standby command in Windows PowerShell as Administrator.',
        '3. Choose console or GUI; let the initial full check finish.',
        '4. Review / Pending fixes opens if fixes are available. Apply only the repairs you approve.',
        '5. Cancel fixes exits review; Cancel remaining fixes finishes the active operation then stops the queue.',
        '6. Open DSC Service isLive Test and check for success and version 4.1.8.',
        '7. Keep the session-log folder shown by the Windows tool; installer details are in dss-install.log.',
        '8. Select those local files in the website help area to combine them into an error text file.',
        '', 'The webpage cannot collect system logs automatically. No logs are uploaded.',
        'If Windows policy blocks the tool, ask IT to approve it.'
    ].join('\r\n'));
    toast('Help guide prepared for download.');
});
$('#log-files').addEventListener('change', () => {
    const files = [...$('#log-files').files];
    $('#log-file-status').textContent = files.length ? `${files.length} local file(s) selected. Nothing is uploaded. Review the exported file before sharing.` : 'No log files selected. Files stay in this browser.';
});
$('#download-error-report').addEventListener('click', async () => {
    const files = [...$('#log-files').files];
    const note = $('#error-notes').value.trim();
    if (!files.length && !note) { toast('Select existing log files or describe the error first.'); return; }
    if (files.reduce((sum, file) => sum + file.size, 0) > 5 * 1024 * 1024) { toast('Select up to 5 MB of log files for one text report.'); return; }
    const button = $('#download-error-report'); button.disabled = true;
    try {
        const sections = ['Digital Signing Service 4.1.8 - User supplied logs / error report', new Date().toISOString(), '', 'Issue description:', note || '(No description supplied)', '', 'These are user-selected files, not an automatic system scan.'];
        for (const file of files) { sections.push('', `--- ${file.name} ---`, await file.text()); }
        saveTextFile('Digital-Service-logs-error.txt', sections.join('\r\n'));
        toast('Local logs / error text prepared. Review private information before sharing.');
    } catch { toast('A selected file could not be read. Try a text log file or enter the issue description.'); }
    finally { button.disabled = false; }
});

$('.file-label').addEventListener('keydown', event => {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); $('#log-files').click(); }
});
