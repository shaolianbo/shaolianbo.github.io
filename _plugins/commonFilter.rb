module Jekyll
	module MyFilter
		def limitHashCount (obj,len=3)
			n=0
			result=[]
			for key in obj
				result.push(key)
				n+=1
				if n>=len
					break
				end
			end
			result
		end
	end # myFilter
end # Jekyll

Liquid::Template.register_filter(Jekyll::MyFilter)
