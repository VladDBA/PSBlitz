function SearchStatsAndIndexFrag() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("StatsOrIxFragTable");
  tr = table.getElementsByTagName("tr");

  // Loop through all table rows, and hide those who don't match the search query
  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[1];
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


function SearchIndexUsage() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("IndexUsgTable");
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

function SearchDeadlockDetails() {
  // Declare variables
  var input, filter, table, tr, td, i, txtValue;
  input = document.getElementById("SearchBox");
  filter = input.value.toUpperCase();
  table = document.getElementById("DeadlockDtlTable");
  tr = table.getElementsByTagName("tr");

  for (i = 0; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td")[7];
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