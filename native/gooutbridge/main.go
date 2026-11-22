package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"os"
	"runtime/debug"
	"time"
	"unsafe"

	libXray "github.com/xtls/libxray"
)

// ---------- ArkTS 侧信封（保持与 stub 一致，Go 内翻译到 libXray） ----------
// Request:  {"action":"RunXray","payload":{...}}
// Response: {"code":0,"data":...} / {"code":-1,"msg":"..."}

type Request struct {
	Action  string          `json:"action"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type Response struct {
	Code int    `json:"code"`
	Msg  string `json:"msg,omitempty"`
	Data any    `json:"data,omitempty"`
}

// libXray invoke 信封
type lxRequest struct {
	APIVersion int             `json:"apiVersion"`
	Method     string          `json:"method"`
	Payload    json.RawMessage `json:"payload,omitempty"`
}

type lxResponse struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Err     string          `json:"error"`
}

func init() {
	// 移动端内存优化：激进 GC + 内存上限 + 定期归还 OS
	debug.SetGCPercent(50)
	debug.SetMemoryLimit(96 << 20)
	go func() {
		for {
			time.Sleep(30 * time.Second)
			debug.FreeOSMemory()
		}
	}()
}

func ok(data any) *C.char {
	b, _ := json.Marshal(Response{Code: 0, Data: data})
	return C.CString(string(b))
}

func fail(format string, args ...any) *C.char {
	b, _ := json.Marshal(Response{Code: -1, Msg: fmt.Sprintf(format, args...)})
	return C.CString(string(b))
}

// lxInvoke 调用 libXray.Invoke 并解析响应
func lxInvoke(method string, payload any) (json.RawMessage, error) {
	var raw json.RawMessage
	if payload != nil {
		b, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		raw = b
	}
	req := lxRequest{APIVersion: 3, Method: method, Payload: raw}
	reqBytes, _ := json.Marshal(req)
	respRaw := libXray.Invoke(string(reqBytes))
	var resp lxResponse
	if err := json.Unmarshal([]byte(respRaw), &resp); err != nil {
		return nil, fmt.Errorf("bad libxray response: %v", err)
	}
	if !resp.Success {
		return nil, fmt.Errorf("%s", resp.Err)
	}
	return resp.Data, nil
}

//export CGoInvoke
func CGoInvoke(req *C.char) *C.char {
	defer func() {
		_ = recover()
	}()
	var r Request
	if err := json.Unmarshal([]byte(C.GoString(req)), &r); err != nil {
		return fail("bad request json: %v", err)
	}
	switch r.Action {
	case "hello":
		return ok("hello from goout bridge (libxray)")
	case "version":
		data, err := lxInvoke("xrayVersion", nil)
		if err != nil {
			return fail("%v", err)
		}
		var v struct {
			Version string `json:"version"`
		}
		if err := json.Unmarshal(data, &v); err != nil {
			return fail("%v", err)
		}
		return ok(v.Version)
	case "RunXray":
		var p struct {
			Xray    string `json:"xray"`
			Datadir string `json:"datadir"`
		}
		if err := json.Unmarshal(r.Payload, &p); err != nil {
			return fail("bad RunXray payload: %v", err)
		}
		if p.Datadir != "" {
			// xray 通过该环境变量定位 geoip.dat / geosite.dat
			os.Setenv("XRAY_LOCATION_ASSET", p.Datadir)
		}
		_, err := lxInvoke("runXray", map[string]string{"xrayJson": p.Xray})
		if err != nil {
			return fail("%v", err)
		}
		return ok("started")
	case "StopXray":
		_, err := lxInvoke("stopXray", nil)
		if err != nil {
			return fail("%v", err)
		}
		return ok("stopped")
	case "GetXrayState":
		data, err := lxInvoke("getXrayState", nil)
		if err != nil {
			return fail("%v", err)
		}
		var s struct {
			Running bool `json:"running"`
		}
		if err := json.Unmarshal(data, &s); err != nil {
			return fail("%v", err)
		}
		return ok(s.Running)
	case "Ping":
		var p struct {
			Xray    string `json:"xray"`
			URL     string `json:"url"`
			Timeout int    `json:"timeout"`
		}
		if err := json.Unmarshal(r.Payload, &p); err != nil {
			return fail("bad Ping payload: %v", err)
		}
		if p.URL == "" {
			p.URL = "https://www.gstatic.com/generate_204"
		}
		if p.Timeout <= 0 {
			p.Timeout = 8
		}
		payload := map[string]any{
			"configs": []map[string]string{{"xrayJson": p.Xray}},
			"timeout": p.Timeout,
			"url":     p.URL,
		}
		data, err := lxInvoke("pingBatch", payload)
		if err != nil {
			return fail("%v", err)
		}
		var resp struct {
			Results []struct {
				Success bool   `json:"success"`
				Delay   int64  `json:"delay"`
				Error   string `json:"error"`
			} `json:"results"`
		}
		if err := json.Unmarshal(data, &resp); err != nil || len(resp.Results) == 0 {
			return fail("bad ping response")
		}
		item := resp.Results[0]
		if !item.Success {
			return ok(map[string]any{"delay": -1, "error": item.Error})
		}
		return ok(map[string]any{"delay": item.Delay})
	default:
		return fail("unknown action: %s", r.Action)
	}
}

//export CGoFree
func CGoFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
