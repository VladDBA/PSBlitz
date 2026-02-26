function SearchTable(tableId, colIndex, inputId) {
    var input = inputId ? document.getElementById(inputId) : document.getElementById('SearchBox');
    if (!input) return;
    var filter = (input.value || '').trim().toLowerCase();
    var table = document.getElementById(tableId);
    if (!table) return;
    var tbody = table.tBodies && table.tBodies.length ? table.tBodies[0] : table;
    var rows = tbody.rows;
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row.querySelector('th')) { row.style.display = ''; continue; }
        var cell = row.cells[colIndex];
        var text = cell ? (cell.textContent || cell.innerText || '') : '';
        row.style.display = text.toLowerCase().indexOf(filter) !== -1 ? '' : 'none';
    }
}