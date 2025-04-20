function SearchDBInfo() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("DBInfoTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[0];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}

function SearchDBFileInfo() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox1");
  filter = input.value.toUpperCase();
  table = document.getElementById("DBFileInfoTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[0];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}

function SearchStorageStats() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("StorageStatsTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[9];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}

function SearchInstanceHealth() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("InstanceHealthTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[3];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}


function SearchPerfmon() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("PerfmonTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[2];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}

//new version of the function to replace all of the above
function SearchTable(tableId, columnIndex) {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById(tableId);
  tr = table.getElementsByTagName("tr");

  // Loop through all table rows, and hide those who don't match the search query
  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[columnIndex];
    if (td) {
      txtValue = td.textContent || td.innerText;
      if (txtValue.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }
  }
}