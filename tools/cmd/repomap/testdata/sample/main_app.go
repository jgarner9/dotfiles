package sample

func run() {
	c := NewCache()
	var s Store = c
	_ = s.Get("a")
	_ = NewCache()
}
