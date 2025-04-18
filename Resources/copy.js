document.addEventListener('DOMContentLoaded', function() {
  const messageElement = document.getElementById('message');

  document.querySelectorAll('.copyButton').forEach(button => {
    button.addEventListener('click', function(event) {
      const tableId = button.getAttribute('data-table-id');
      const columnIndex = parseInt(button.getAttribute('data-column-index'), 10);

      const table = document.getElementById(tableId);
      if (!table) {
        console.error('Table not found:', tableId);
        return;
      }

      const rows = table.getElementsByTagName('tr');
      let columnValues = [];

      for (let row of rows) {
        const cell = row.getElementsByTagName('td')[columnIndex];
        if (cell && cell.innerText.trim() !== '') {
          columnValues.push(cell.innerText.trim());
        }
      }

      const columnText = columnValues.join('\n');
      console.log('Text to copy:', columnText); // Log the text to be copied

      navigator.clipboard.writeText(columnText).then(function() {
        // Position the message near the clicked button
        const buttonRect = button.getBoundingClientRect();
        messageElement.style.left = `${buttonRect.left + window.scrollX}px`;
        messageElement.style.top = `${buttonRect.bottom + window.scrollY + 10}px`;
        messageElement.classList.add('show');
        setTimeout(() => {
          messageElement.classList.remove('show');
        }, 1000); // Hide the message after 2 seconds
      }).catch(function(err) {
        console.error('Could not copy text: ', err);
      });
    });
  });
});