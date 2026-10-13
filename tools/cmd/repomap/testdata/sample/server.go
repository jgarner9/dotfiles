package sample

type Store interface {
	Get(key string) string
}

type Cache struct{ items map[string]string }

func NewCache() *Cache { return &Cache{items: map[string]string{}} }

func (c *Cache) Get(key string) string { return c.items[key] }

func helper() {}
