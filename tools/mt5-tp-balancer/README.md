# TP Balancer – EA MT5 cân TP theo tổng SL

EA quản lý **lệnh vào tay** (Magic = 0, không comment) trên chart đang gắn. Mỗi khi chuỗi khớp thêm một bậc, EA tính lại TP chung để **tổng lời tại TP = tổng lỗ tại SL × RR**.

## Logic
- **SL chung:** anh đặt hoặc sửa SL ở bất kỳ lệnh nào trong chuỗi, EA sẽ áp SL đó cho cả chuỗi.
- **TP chung:** `TP = Giá TB − (SL − Giá TB) × RR` với lệnh Sell, ngược lại với lệnh Buy. Giá TB tính theo khối lượng.
- **Anh tự sửa hoặc xoá TP một lệnh:** EA đánh dấu ✋ và không đụng vào TP lệnh đó nữa. TP các lệnh còn lại được tính lại cho cân với nhau.
- **Chu kỳ đã có lệnh chốt lời:** chu kỳ bị đóng băng, EA không chỉnh SL/TP nữa.
- **Chu kỳ mới** bắt đầu khi có một trong các điều kiện sau:
  1. Không còn lệnh nào của chu kỳ cũ đang mở.
  2. Vào lệnh **0.01** (InpStartLot) **sau khi chu kỳ cũ đã chốt lời**.
  3. Vào lệnh ngược chiều.
  4. Bấm nút **CHU KỲ MỚI** trên chart.
- **Lệnh 0.01 vào giữa chuỗi khi chưa chốt lời** (ví dụ chia 0.03 thành 0.01 + 0.02) vẫn được tính chung chuỗi.
- **EA nhận nhầm lệnh là chu kỳ mới:** bấm **GỘP LỆNH CUỐI** để đưa lệnh vừa vào về chu kỳ trước.
- Trạng thái lưu trong Global Variables, nên tắt hoặc mở lại MT5 không bị mất.

## Cài EA
1. Copy `TPBalancer.mq5` vào `MQL5/Experts/`, mở MetaEditor rồi bấm Compile.
2. Gắn EA vào chart XAUUSD và bật Algo Trading.
3. Đặt SL cho lệnh đầu tiên. EA sẽ tự lo các lệnh sau.

## Web theo dõi online (miễn phí, chạy trên Google)
1. Tạo một Google Sheet mới, vào **Extensions → Apps Script**.
2. Dán nội dung `web/Code.gs` vào file `Code.gs`. Tạo file HTML tên `Dashboard` rồi dán nội dung `web/Dashboard.html`.
3. Sửa `WEB_KEY` và `VIEW_PIN`.
4. Vào **Deploy → New deployment → Web app**, chọn Execute as: *Me*, Who has access: *Anyone*. Copy URL `.../exec`.
5. Trong MT5 trên VPS, vào **Tools → Options → Expert Advisors**, tick *Allow WebRequest* và thêm `https://script.google.com` cùng `https://script.googleusercontent.com`.
6. Trong input của EA: dán URL vào `InpWebUrl` và đặt `InpWebKey` trùng với `WEB_KEY`.
7. Mở URL web app trên điện thoại, nhập PIN để xem.
