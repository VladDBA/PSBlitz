/* ------------------------------------------------------------------
   copy.js – unified copy handling for:
   1Column-wide copy (your original implementation)
   2Row-specific copy (button inside the Query Name cell)
------------------------------------------------------------------ */

document.addEventListener('DOMContentLoaded', function () {
  const messageElement = document.getElementById('message');

  /* --------------------------------------------------------------
     Helper: show the temporary "Copied!" tooltip near a button
  -------------------------------------------------------------- */
  function showCopyMessage(btn) {
    const rect = btn.getBoundingClientRect();
    messageElement.style.left = `${rect.left + window.scrollX}px`;
    messageElement.style.top = `${rect.bottom + window.scrollY + 10}px`;
    messageElement.classList.add('show');
    setTimeout(() => messageElement.classList.remove('show'), 1000);
  }

  /* --------------------------------------------------------------
     1Column-wide copy - keep your original logic unchanged
  -------------------------------------------------------------- */
  document.querySelectorAll('.copyButton').forEach(button => {
    button.addEventListener('click', function () {
      const tableId = button.getAttribute('data-table-id');
      const columnIndex = parseInt(button.getAttribute('data-column-index'), 10);
      const table = document.getElementById(tableId);

      if (!table) {
        console.error('Table not found:', tableId);
        return;
      }

      const rows = table.getElementsByTagName('tr');
      const columnValues = [];

      for (let row of rows) {
        const cell = row.getElementsByTagName('td')[columnIndex];
        if (cell && cell.innerText.trim() !== '') {
          columnValues.push(cell.innerText.trim());
        }
      }

      const columnText = columnValues.join('\n');
      console.log('Text to copy (column):', columnText);

      navigator.clipboard.writeText(columnText)
        .then(() => showCopyMessage(button))
        .catch(err => console.error('Could not copy column text:', err));
    });
  });

  /* --------------------------------------------------------------
     2Row-specific copy – new logic for the button inside the name cell
        Use class "copyBtnRow" (or reuse "copyButton" if you prefer)
  -------------------------------------------------------------- */
  document.querySelectorAll('.copyBtnRow').forEach(button => {
    button.addEventListener('click', function () {
      // Find the row that contains this button
      const row = button.closest('tr');
      if (!row) {
        console.error('Button not inside a table row');
        return;
      }

      // Assuming the query text is in the second cell (index 1)
      const queryCell = row.cells[1];
      if (!queryCell) {
        console.error('Expected query text cell missing');
        return;
      }

      const queryText = queryCell.textContent.trim();
      console.log('Text to copy (row):', queryText);

      navigator.clipboard.writeText(queryText)
        .then(() => {
          const originalLabel = button.textContent; 
          button.textContent = 'Copied!';
          setTimeout(() => {
            button.textContent = originalLabel;
          }, 750);
        })
        .catch(err => console.error('Could not copy row text:', err));
    });
  });
});