'use strict';
for (const button of document.querySelectorAll('[data-copy]')) {
  button.addEventListener('click', async () => {
    const command = document.getElementById(button.dataset.copy);
    const status = document.getElementById('copy-status');
    if (!command) return;
    try {
      await navigator.clipboard.writeText(command.textContent);
      button.textContent = 'Copied';
      status.textContent = 'Command copied. Replace the example folder with your own.';
      setTimeout(() => { button.textContent = 'Copy command'; }, 2500);
    } catch {
      button.textContent = 'Select the command to copy';
      status.textContent = 'Clipboard access is unavailable. Select and copy the command manually.';
    }
  });
}
