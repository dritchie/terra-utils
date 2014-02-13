
CC=clang++
SO=liblinsolve.so

# CFLAGS=

HEADERS=\
	exports.h

CPP=\
	exports.cpp

OBJ=$(CPP:.cpp=.o)

all: $(SO)

clean:
	rm -f *.o *.so

$(SO): $(OBJ)
	$(CC) -shared $(OBJ) -o $@

%.o: %.cpp $(HEADERS)
	$(CC) $(CFLAGS) -c -O3 $*.cpp -o $@