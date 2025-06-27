// my_project/web-frontend/html/script.js
function fetchApiData() {
    const loadingIndicator = document.getElementById('loadingIndicator');
    const tableBody = document.getElementById('tableBody');
    loadingIndicator.classList.remove('hidden');
    tableBody.innerHTML = ''; // 清空舊資料

    fetch('/api/data')
        .then(response => {
            loadingIndicator.classList.add('hidden'); // 隱藏載入指示
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            if (data && data.passengers) {
                data.passengers.forEach(passenger => {
                    const row = tableBody.insertRow();
                    row.className = 'border-b border-gray-200 hover:bg-gray-100';
                    row.innerHTML = `
                        <td class="py-3 px-6 text-left whitespace-nowrap">${passenger.PassengerId}</td>
                        <td class="py-3 px-6 text-left whitespace-nowrap">${passenger.Name}</td>
                        <td class="py-3 px-6 text-left">${passenger.Sex}</td>
                        <td class="py-3 px-6 text-left">${passenger.Age !== null ? passenger.Age : 'N/A'}</td>
                        <td class="py-3 px-6 text-left">${passenger.Survived === 1 ? '是' : '否'}</td>
                        <td class="py-3 px-6 text-left">${passenger.Pclass}</td>
                        <td class="py-3 px-6 text-left">${passenger.Fare}</td>
                    `;
                });
            } else {
                tableBody.innerHTML = '<tr><td colspan="7" class="py-3 px-6 text-center">沒有找到乘客資料。</td></tr>';
            }
        })
        .catch(error => {
            console.error('Error fetching API data:', error);
            loadingIndicator.classList.add('hidden');
            tableBody.innerHTML = `<tr><td colspan="7" class="py-3 px-6 text-center text-red-500">載入資料失敗: ${error.message}</td></tr>`;
        });
}

// 在頁面載入完成後綁定事件監聽器
document.addEventListener('DOMContentLoaded', () => {
    const fetchDataBtn = document.getElementById('fetchDataBtn');
    if (fetchDataBtn) {
        fetchDataBtn.addEventListener('click', fetchApiData);
    }
});