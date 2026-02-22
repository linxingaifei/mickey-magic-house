# alpine-base-template

一個可直接新建倉庫使用的 Alpine 底層模板。

## 內容

- `Dockerfile`：基於 `alpine:3.20`
- `scripts/entrypoint.sh`：簡單 entrypoint
- `.github/workflows/docker-image.yml`：自動建置檢查

## 本地測試

```bash
docker build -t alpine-base-template .
docker run --rm alpine-base-template sh -lc 'cat /etc/alpine-release && echo ok'
```

## 建議新倉庫建立流程

1. 在 GitHub 新建倉庫（例如 `alpine-base-template`）。
2. 複製本資料夾內容到新倉庫根目錄。
3. 修改 Dockerfile 的 `org.opencontainers.image.source`。
4. push 後由 GitHub Actions 自動執行 build 驗證。
