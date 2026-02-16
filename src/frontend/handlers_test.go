package main

import (
	"testing"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/frontend/genproto"
)

func TestRenderMoneyBRL(t *testing.T) {
	tests := []struct {
		name string
		in   pb.Money
		want string
	}{
		{
			name: "basic",
			in:   pb.Money{CurrencyCode: "BRL", Units: 1234, Nanos: 560000000},
			want: "R$ 1.234,56",
		},
		{
			name: "large number",
			in:   pb.Money{CurrencyCode: "BRL", Units: 1234567, Nanos: 0},
			want: "R$ 1.234.567,00",
		},
		{
			name: "negative",
			in:   pb.Money{CurrencyCode: "BRL", Units: -9876, Nanos: -540000000},
			want: "R$ -9.876,54",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := renderMoney(tt.in)
			if got != tt.want {
				t.Fatalf("renderMoney() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestRenderMoneyNonBRLUnchanged(t *testing.T) {
	in := pb.Money{CurrencyCode: "USD", Units: 1234, Nanos: 560000000}
	want := "$1234.56"

	got := renderMoney(in)
	if got != want {
		t.Fatalf("renderMoney() = %q, want %q", got, want)
	}
}

