; Jolt Standard Library: jolt.http
; HTTP client using Janet's net/ module.

(defn get
  [url & {:keys [headers]}]
  (let [result (net/request url :get headers {})]
    {:status (result :status) :body (result :body) :headers (result :headers)}))

(defn post
  [url body & {:keys [headers]}]
  (let [result (net/request url :post headers body)]
    {:status (result :status) :body (result :body) :headers (result :headers)}))
